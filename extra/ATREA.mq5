#include <Trade\Trade.mqh>

CTrade trade;

// Define Session Times
#define LONDON_OPEN 8   // 8 AM GMT
#define LONDON_CLOSE 16 // 4 PM GMT
#define NY_OPEN 13      // 1 PM GMT
#define NY_CLOSE 22     // 10 PM GMT

input int InpAtrPeriod = 14;    // ATR period
input int InpAtrMultiplier = 5; // ATR multiplier

double lastHmaArrayUp = -1;
double lastHmaArrayDn = -1;
bool tradePlaced = false;
bool canPlaceBuy = true;
bool canPlaceSell = true;

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

    datetime curTimeSeconds = (curTime % 86400); // seconds since midnight

    // Check if the current time is within the London or New York session times.
    if ((curTimeSeconds >= londonOpen && curTimeSeconds <= londonClose) || (curTimeSeconds >= nyOpen && curTimeSeconds <= nyClose))
        return true;

    return false;
}

void OnTick()
{
    // Check if trading is allowed
    if (!IsTradingAllowed())
        return;
    double hmaArrayUp[2];
    double hmaArrayDn[2];
    CopyBuffer(iCustom(_Symbol, _Period, "ATRStopLoss_Ind", InpAtrPeriod, 5, InpAtrMultiplier), 0, 0, 2, hmaArrayUp);
    CopyBuffer(iCustom(_Symbol, _Period, "ATRStopLoss_Ind", InpAtrPeriod, 5, InpAtrMultiplier), 1, 0, 2, hmaArrayDn);

    double closeArray[2];
    if (CopyClose(_Symbol, _Period, 0, 2, closeArray) == -1)
    {
        Print("Error copying close prices: ", GetLastError());
        return;
    }

    double currentClose = closeArray[0];

    bool validBuyCondition = (hmaArrayUp[0] != 1.7976931348623157e+308 && currentClose > hmaArrayUp[0]);
    bool validSellCondition = (hmaArrayDn[0] != 1.7976931348623157e+308 && currentClose < hmaArrayDn[0]);

    // Check if the HMA values have changed
    if (hmaArrayUp[0] != lastHmaArrayUp)
    {
        canPlaceBuy = true;
        lastHmaArrayUp = hmaArrayUp[0];
    }

    if (hmaArrayDn[0] != lastHmaArrayDn)
    {
        canPlaceSell = true;
        lastHmaArrayDn = hmaArrayDn[0];
    }

    if (!tradePlaced)
    {
        double stopLossPips = 80.0;
        double stopLossPrice;

        if (validBuyCondition && canPlaceBuy)
        {
            double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            stopLossPrice = askPrice - stopLossPips * _Point;
            trade.Buy(0.01, _Symbol, askPrice, stopLossPrice, 0);
            tradePlaced = true;
            canPlaceBuy = false;
        }
        else if (validSellCondition && canPlaceSell)
        {
            double bidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            stopLossPrice = bidPrice + stopLossPips * _Point;
            trade.Sell(0.01, _Symbol, bidPrice, stopLossPrice, 0);
            tradePlaced = true;
            canPlaceSell = false;
        }
    }

    if (PositionsTotal() == 0)
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
                    trade.PositionModify(ticket, hmaArrayUp[0], PositionGetDouble(POSITION_TP));
                    break;
                case POSITION_TYPE_SELL:
                    trade.PositionModify(ticket, hmaArrayDn[0], PositionGetDouble(POSITION_TP));
                    break;
                default:
                    break;
                }
            }
        }
    }
}
