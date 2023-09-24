// Need to implement trailing stops, main function done

#include <Trade\Trade.mqh>
CTrade trade;

input int InpAtrPeriod = 14;
input int InpAtrMultiplier = 5;

double lastHmaArrayUp = -1;
double lastHmaArrayDn = -1;
ulong buyLimitOrder = 0;
ulong sellLimitOrder = 0;

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    double hmaArrayUp[2];
    double hmaArrayDn[2];
    CopyBuffer(iCustom(_Symbol, _Period, "ATRStopLoss_Ind", InpAtrPeriod, InpAtrMultiplier), 0, 0, 2, hmaArrayUp);
    CopyBuffer(iCustom(_Symbol, _Period, "ATRStopLoss_Ind", InpAtrPeriod, InpAtrMultiplier), 1, 0, 2, hmaArrayDn);

    if (hmaArrayUp[0] != lastHmaArrayUp)
    {
        if(buyLimitOrder != 0)
            trade.OrderDelete(buyLimitOrder);

        double limitPrice = lastHmaArrayUp; // Adjust according to your strategy
        buyLimitOrder = trade.BuyLimit(0.01, limitPrice, _Symbol); // Place buy limit order
        lastHmaArrayUp = hmaArrayUp[0];
    }

    if (hmaArrayDn[0] != lastHmaArrayDn)
    {
        if(sellLimitOrder != 0)
            trade.OrderDelete(sellLimitOrder);

        double limitPrice = lastHmaArrayDn; // Adjust according to your strategy
        sellLimitOrder = trade.SellLimit(0.01, limitPrice, _Symbol); // Place sell limit order
        lastHmaArrayDn = hmaArrayDn[0];
    }

    ManageOrdersAndPositions();
}

void ManageOrdersAndPositions()
{
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong orderTicket = OrderGetTicket(i);
        if(orderTicket > 0) // Check if the ticket is valid
        {
            string symbol = OrderGetString(ORDER_SYMBOL); // Correctly get symbol as a string
            ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
            
            if(symbol == _Symbol)
            {
                if(orderType == ORDER_TYPE_BUY_LIMIT)
                {
                    if(sellLimitOrder != 0)
                        trade.OrderDelete(sellLimitOrder);
                    // Modify or Close Order Logic for Buy Limit
                }
                else if(orderType == ORDER_TYPE_SELL_LIMIT)
                {
                    if(buyLimitOrder != 0)
                        trade.OrderDelete(buyLimitOrder);
                    // Modify or Close Order Logic for Sell Limit
                }
            }
        }
    }
}


