#include <Trade\Trade.mqh>
#include <Datetime.mqh>
#resource "\\ATRStopLoss_Ind.ex5"

CTrade trade;

// Define Session Times
#define LONDON_OPEN 8   // 8 AM GMT
#define LONDON_CLOSE 16 // 4 PM GMT
#define NY_OPEN 13      // 1 PM GMT
#define NY_CLOSE 22     // 10 PM GMT
#define SYDNEY_OPEN 21   // 9 PM GMT
#define SYDNEY_CLOSE 6   // 6 AM GMT
#define TOKYO_OPEN 23    // 11 PM GMT
#define TOKYO_CLOSE 8    // 8 AM GMT
#define EXCLUDED_START 16  // 4 PM GMT
#define EXCLUDED_END 20    // 8 PM GMT
#define TRADING_START 12  // 3 PM GMT
#define TRADING_END 14    // 5 PM GMT


input float InpAtrLength = 1;    // ATR Length
input float InpAtrPeriod = 5;    // ATR Period
input float InpAtrMultiplier = 1; // ATR multiplier

input float limitPriceGap = 400;
input float stopLossPips = 600.0;

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
    datetime tradingStart = (TRADING_START) * 60 * 60;
    datetime tradingEnd = (TRADING_END + 1) * 60 * 60; // include the 17:00 hour

    datetime curTimeSeconds = (curTime % 86400); // seconds since midnight
    
    if (curTimeSeconds >= tradingStart && curTimeSeconds < tradingEnd)
        return true;

    return false;
}

bool CheckPositions()
{
    if(PositionsTotal() > 0) // if there are open positions
        return true; // continue with logic
    
    return false; // no open positions
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{   
    // It is outside trading hours, check for open positions
    if (!IsTradingAllowed() && !CheckPositions())
    {
        Print("Outside trading hours and no open positions. Exiting function.");
        return;
    }
    
    int rates_total = Bars(_Symbol, _Period);         // Get the number of bars in the current chart
    datetime Time[];                                  // Array to store the time values
    CopyTime(_Symbol, _Period, 0, rates_total, Time); // Copy the time values to the array
    
    // Delete all pending orders after 10 minutes
    for(int i=OrdersTotal()-1; i>=0; i--)
    {
        ulong ticket;
        if (ticket != INVALID_HANDLE){
            ticket = OrderGetTicket(i);
            if (ticket != INVALID_HANDLE)
            {
                ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
                if (orderType == ORDER_TYPE_BUY_STOP || orderType == ORDER_TYPE_SELL_STOP)
                {
                    datetime orderTime = OrderGetInteger(ORDER_TIME_SETUP);
                    if (TimeCurrent() - orderTime > 300)
                    {
                        trade.OrderDelete(ticket);
                    }
                }
            }
        }
    }

    Print("Trade Placed: ", tradePlaced);    // Print the value of tradePlaced
    Print("Can Place Buy: ", canPlaceBuy);   // Print the value of canPlaceBuy
    Print("Can Place Sell: ", canPlaceSell); // Print the value of canPlaceSell

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
                switch (positionType)
                {
                case POSITION_TYPE_BUY:
                    trade.PositionModify(ticket, ATRStopLossUpBuffer[0], PositionGetDouble(POSITION_TP));
                    break;
                case POSITION_TYPE_SELL:
                    trade.PositionModify(ticket, ATRStopLossDnBuffer[0], PositionGetDouble(POSITION_TP));
                    break;
                default:
                    break;
                }
            }
        }
    }

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

            Print("Buy Stop Price: ", BuyStopPrice);   // Print the value of BuyStopPrice
            Print("Stop Loss Price: ", stopLossPrice); // Print the value of stopLossPrice
            // Ensure the BuyStopPrice is above the current market price
            if (BuyStopPrice > askPrice)
            {
                buyLimitTicket = trade.BuyStop(0.02, BuyStopPrice, _Symbol, stopLossPrice, 0); // Use BuyStop
                // If a buy stop order is placed successfully, delete any existing sell stop order
                if (buyLimitTicket > 0 && sellLimitTicket > 0)
                {
                    trade.OrderDelete(sellLimitTicket);
                    sellLimitTicket = 0; // Reset the sellLimitTicket
                }
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

            Print("Sell Stop Price: ", SellStopPrice); // Print the value of SellStopPrice
            Print("Stop Loss Price: ", stopLossPrice); // Print the value of stopLossPrice

            // Ensure the SellStopPrice is below the current market price
            if (SellStopPrice < bidPrice)
            {
                sellLimitTicket = trade.SellStop(0.02, SellStopPrice, _Symbol, stopLossPrice, 0); // Use SellStop
                // If a sell stop order is placed successfully, delete any existing buy stop order
                if (sellLimitTicket > 0 && buyLimitTicket > 0)
                {
                    trade.OrderDelete(buyLimitTicket);
                    buyLimitTicket = 0; // Reset the buyLimitTicket
                }
                sellLimitTime = TimeCurrent(); // Store the time the sell stop order was placed
                tradePlaced = true;
                canPlaceSell = false;
                canPlaceBuy = false;
            }
        }
    }
    
}
