// ----------------------------------------------
// Golden Strategist Expert Advisor (GSEA) Summary
// ----------------------------------------------
// Purpose: Automated trading algorithm specialized in trading gold (XAU/USD)
//          during the most profitable New York sessions.
//
// Core Strategy:
//   - Focuses on sessions where gold exhibits strong trending behaviors.
//   - Employs dynamic trailing stops to maximize profits and minimize losses.
//   - Utilizes stringent risk management techniques with predefined stop-loss
//     and take-profit levels.
//
// Author: MavenFX
#property version "1.0"

#include <Trade\Trade.mqh>
#include <Datetime.mqh>

#resource "\\ATRStopLoss_Ind.ex5"

CTrade trade;

// Define Session Times
#define LONDON_OPEN 8     // 8 AM GMT
#define LONDON_CLOSE 16   // 4 PM GMT
#define NY_OPEN 13        // 1 PM GMT
#define NY_CLOSE 22       // 10 PM GMT
#define SYDNEY_OPEN 21    // 9 PM GMT
#define SYDNEY_CLOSE 6    // 6 AM GMT
#define TOKYO_OPEN 23     // 11 PM GMT
#define TOKYO_CLOSE 8     // 8 AM GMT
#define EXCLUDED_START 16 // 4 PM GMT
#define EXCLUDED_END 20   // 8 PM GMT
#define TRADING_START 12  // 3 PM GMT
#define TRADING_END 14    // 5 PM GMT

input float InpAtrLength = 1;     // ATR Length
input float InpAtrPeriod = 5;     // ATR Period
input float InpAtrMultiplier = 1; // ATR multiplier

input float limitPriceGap = 200;
input float stopLossPips = 300.0;

input float lotSize = 0.02; // Lot Size

double lastStopLossArrayUp = -1;
double lastStopLossArrayDn = -1;
ulong buyLimitOrder = 0;
ulong sellLimitOrder = 0;
bool tradePlaced = false;
bool canPlaceBuy = true;
bool canPlaceSell = true;

ulong buyLimitTicket = 0;
ulong sellLimitTicket = 0;

datetime buyLimitTime = 0;  // Track the time BuyStop was placed
datetime sellLimitTime = 0; // Track the time SellStop was placed

//+------------------------------------------------------------------+
//| Check if it is allowed to trade according to the session times   |
//+------------------------------------------------------------------+
bool IsTradingAllowed()
{
    datetime curTime = TimeCurrent();
    datetime londonOpen = LONDON_OPEN * 60 * 60;
    datetime londonClose = LONDON_CLOSE * 60 * 60;
    datetime nyOpen = NY_OPEN * 60 * 60;
    datetime nyClose = NY_CLOSE * 60 * 60;
    datetime sydneyOpen = SYDNEY_OPEN * 60 * 60;
    datetime sydneyClose = SYDNEY_CLOSE * 60 * 60;
    datetime tokyoOpen = TOKYO_OPEN * 60 * 60;
    datetime tokyoClose = TOKYO_CLOSE * 60 * 60;
    datetime excludedStart = EXCLUDED_START * 60 * 60;
    datetime excludedEnd = EXCLUDED_END * 60 * 60;
    datetime tradingStart = (TRADING_START)*60 * 60;
    datetime tradingEnd = (TRADING_END + 1) * 60 * 60; // include the 17:00 hour

    datetime curTimeSeconds = (curTime % 86400); // seconds since midnight

    if (curTimeSeconds >= tradingStart && curTimeSeconds < tradingEnd)
        return true;

    return false;
}

bool CheckPositions()
{
    if (PositionsTotal() > 0) // if there are open positions
        return true;          // continue with logic

    return false; // no open positions
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    It is outside trading hours, check for open positions
    if (!IsTradingAllowed() && !CheckPositions())
    {
        Print("Outside trading hours and no open positions. Exiting function.");
        return;
    }

    double freeMargin = AccountInfoDouble(ACCOUNT_FREEMARGIN);
    double marginRequired = SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_INITIAL) * lotSize;

    if (freeMargin < marginRequired)
    {
        Print("Not enough money");
        return; // Skip placing the trade
    }

    int rates_total = Bars(_Symbol, _Period);         // Get the number of bars in the current chart
    datetime Time[];                                  // Array to store the time values
    CopyTime(_Symbol, _Period, 0, rates_total, Time); // Copy the time values to the array

    // Delete all pending orders after 5 minutes
    for (int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if (ticket != INVALID_HANDLE)
        {
            ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
            if (orderType == ORDER_TYPE_BUY_STOP || orderType == ORDER_TYPE_SELL_STOP)
            {
                datetime orderTime = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
                if (TimeCurrent() - orderTime > 300) // 5minutes in seconds
                {
                    if (OrderGetTicket(i) != INVALID_HANDLE) // Check again if the order still exists
                    {
                        if (!trade.OrderDelete(ticket))
                        {
                            Print("Failed to delete order #", ticket, " Error code: ", GetLastError());
                        }
                    }
                }
            }
        }
    }

    double ATRStopLossUpBuffer[2];
    double ATRStopLossDnBuffer[2];
    CopyBuffer(iCustom(_Symbol, _Period, "::ATRStopLoss_Ind.ex5", InpAtrLength, InpAtrPeriod, InpAtrMultiplier), 0, 0, 2, ATRStopLossUpBuffer);
    CopyBuffer(iCustom(_Symbol, _Period, "::ATRStopLoss_Ind.ex5", InpAtrLength, InpAtrPeriod, InpAtrMultiplier), 1, 0, 2, ATRStopLossDnBuffer);

    double closeArray[2];
    if (CopyClose(_Symbol, _Period, 0, 2, closeArray) == -1)
    {
        Print("Error copying close prices: ", GetLastError());
        return;
    }

    double currentClose = closeArray[0];

    bool validBuyCondition = (ATRStopLossUpBuffer[0] != 1.7976931348623157e+308 && currentClose > ATRStopLossUpBuffer[0]);
    bool validSellCondition = (ATRStopLossDnBuffer[0] != 1.7976931348623157e+308 && currentClose < ATRStopLossDnBuffer[0]);

    // Check if the HMA values have changed
    if (ATRStopLossUpBuffer[0] != lastStopLossArrayUp)
    {
        canPlaceBuy = true;
        lastStopLossArrayUp = ATRStopLossUpBuffer[0];
    }

    if (ATRStopLossDnBuffer[0] != lastStopLossArrayDn)
    {
        canPlaceSell = true;
        lastStopLossArrayDn = ATRStopLossDnBuffer[0];
    }

    if (PositionsTotal() == 0 && OrdersTotal() == 0)
    {
        tradePlaced = false;
    }

    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (ticket != INVALID_HANDLE)
        {
            string symbol = PositionGetString(POSITION_SYMBOL);
            if (symbol == _Symbol)
            {
                ENUM_POSITION_TYPE positionType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                double currentSL = NormalizeDouble(PositionGetDouble(POSITION_SL), _Digits); // Gets the current stop loss value of the position

                switch (positionType)
                {
                case POSITION_TYPE_BUY:
                {
                    double newBuySL = NormalizeDouble(ATRStopLossUpBuffer[0], _Digits); // Normalizing to match decimal places of _Digits

                    // if (newBuySL == currentSL || newBuySL < currentSL)
                    //     return; // Exit if no modification is necessary
                    


                    Print("Current SL: ", currentSL, " New SL: ", newBuySL);
                    // ensure SL is not "1.7976931348623157e+308"
                    if (currentSL != newBuySL && newBuySL != 1.7976931348623157e+308 ) // Checks if the current stop loss is different from the new stop loss value
                    {
                        if (trade.PositionModify(ticket, newBuySL, PositionGetDouble(POSITION_TP)))
                        {
                            Print("Successfully modified #", ticket, " to SL:", newBuySL);
                        }
                    }
                }
                break;
                case POSITION_TYPE_SELL:
                {
                    double newSellSL = NormalizeDouble(ATRStopLossDnBuffer[0], _Digits); // Normalizing to match decimal places of _Digits

                    // if (newSellSL == currentSL || newSellSL > currentSL)
                    //     return; // Exit if no modification is necessary

                    // print the current stop loss and the new stop loss
                    Print("Current SL: ", currentSL, " New SL: ", newSellSL);

                    if (currentSL != newSellSL && newSellSL != 1.7976931348623157e+308) // Checks if the current stop loss is different from the new stop loss value
                    {
                        if (trade.PositionModify(ticket, newSellSL, PositionGetDouble(POSITION_TP)))
                        {
                            Print("Successfully modified #", ticket, " to SL:", newSellSL);
                        }
                    }
                }
                break;
                default:
                    continue;
                }
            }
        }
    }

    // for (int i = PositionsTotal() - 1; i >= 0; i--)
    // {
    //     ulong ticket = PositionGetTicket(i);
    //     if (ticket != INVALID_HANDLE)
    //     {
    //         string symbol = PositionGetString(POSITION_SYMBOL);
    //         if (symbol == _Symbol)
    //         {
    //             ENUM_POSITION_TYPE positionType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    //             switch (positionType)
    //             {
    //             case POSITION_TYPE_BUY:
    //                 trade.PositionModify(ticket, ATRStopLossUpBuffer[0], PositionGetDouble(POSITION_TP));
    //                 break;
    //             case POSITION_TYPE_SELL:
    //                 trade.PositionModify(ticket, ATRStopLossDnBuffer[0], PositionGetDouble(POSITION_TP));
    //                 break;
    //             default:
    //                 break;
    //             }
    //         }
    //     }
    // }

    if (tradePlaced == false)
    {
        double stopLossPrice;

        double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

        if (validBuyCondition && canPlaceBuy)
        {
            double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            stopLossPrice = askPrice - stopLossPips * _Point;
            double BuyStopPrice = NormalizeDouble(askPrice + (limitPriceGap * _Point), _Digits); // Adjust for BuyStop
            stopLossPrice = NormalizeDouble(BuyStopPrice - (stopLossPips * _Point), _Digits);    // Calculate stop loss from BuyStopPrice

            // Ensure the BuyStopPrice is above the current market price
            if (BuyStopPrice > askPrice)
            {
                buyLimitTicket = trade.BuyStop(lotSize, BuyStopPrice, _Symbol, stopLossPrice, 0); // Use BuyStop

                buyLimitTime = TimeCurrent(); // Store the time the buy stop order was placed
                tradePlaced = true;
                canPlaceBuy = false;
                canPlaceSell = false;
            }
        }
        else if (validSellCondition && canPlaceSell)
        {
            double bidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            stopLossPrice = bidPrice + stopLossPips * _Point;
            double SellStopPrice = NormalizeDouble(bidPrice - (limitPriceGap * _Point), _Digits); // Adjust for SellStop
            stopLossPrice = NormalizeDouble(SellStopPrice + (stopLossPips * _Point), _Digits);    // Calculate stop loss from SellStopPrice

            // Ensure the SellStopPrice is below the current market price
            if (SellStopPrice < bidPrice)
            {
                sellLimitTicket = trade.SellStop(lotSize, SellStopPrice, _Symbol, stopLossPrice, 0); // Use SellStop

                sellLimitTime = TimeCurrent(); // Store the time the sell stop order was placed
                tradePlaced = true;
                canPlaceSell = false;
                canPlaceBuy = false;
            }
        }
    }
}
