// Your EA file

#include <GlobalVariables.mqh>
#include "../Include/HMAInclude.mqh"
#include <Trade\Trade.mqh>
#include <Datetime.mqh>

CTrade trade;
datetime lastTradeTime = 0;

string gvPeriod = "gvHMA_Period";
string gvDivisor = "gvHMA_Divisor";
string gvPrice = "gvHMA_Price";

input int HMA_Period = 100;
input double HMA_Divisor = 2.0;
input ENUM_APPLIED_PRICE HMA_Price = PRICE_CLOSE;

//--- indicator settings
#property indicator_separate_window
#property indicator_buffers 2
#property indicator_plots 1
#property indicator_type1 DRAW_LINE
#property indicator_color1 DodgerBlue
#property indicator_label1 "ATR"
//--- input parameters
input int InpAtrPeriod = 14; // ATR period
//--- indicator buffers
double ExtATRBuffer[];
double ExtTRBuffer[];
//--- global variable
int ExtPeriodATR;

long hmaHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
void ATR_OnInit()
{
    //--- check for input value
    if (InpAtrPeriod <= 0)
    {
        ExtPeriodATR = 14;
        printf("Incorrect input parameter InpAtrPeriod = %d. Indicator will use value %d for calculations.", InpAtrPeriod, ExtPeriodATR);
    }
    else
        ExtPeriodATR = InpAtrPeriod;
    //--- indicator buffers mapping
    SetIndexBuffer(0, ExtATRBuffer, INDICATOR_DATA);
    SetIndexBuffer(1, ExtTRBuffer, INDICATOR_CALCULATIONS);
    //---
    IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
    //--- sets first bar from what index will be drawn
    PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, InpAtrPeriod);
    //--- name for DataWindow and indicator subwindow label
    string short_name = "ATR(" + string(ExtPeriodATR) + ")";
    IndicatorSetString(INDICATOR_SHORTNAME, short_name);
    PlotIndexSetString(0, PLOT_LABEL, short_name);
    //--- initialization done
}

//+------------------------------------------------------------------+
//| Average True Range                                               |
//+------------------------------------------------------------------+
int ATR_OnCalculate(const int rates_total,
                    const int prev_calculated,
                    const datetime &Time[],
                    const double &Open[],
                    const double &High[],
                    const double &Low[],
                    const double &Close[],
                    const long &TickVolume[],
                    const long &Volume[],
                    const int &Spread[])
{
    ArrayResize(ExtATRBuffer, rates_total);
    ArrayResize(ExtTRBuffer, rates_total);

    int i, limit;
    //--- check for bars count
    if (rates_total <= ExtPeriodATR)
        return (0); // not enough bars for calculation
                    //--- preliminary calculations
    if (prev_calculated == 0)
    {
        ExtTRBuffer[0] = 0.0;
        ExtATRBuffer[0] = 0.0;
        //--- filling out the array of True Range values for each period
        for (i = 1; i < rates_total && !IsStopped(); i++)
            ExtTRBuffer[i] = MathMax(High[i], Close[i - 1]) - MathMin(Low[i], Close[i - 1]);
        //--- first AtrPeriod values of the indicator are not calculated
        double firstValue = 0.0;
        for (i = 1; i <= ExtPeriodATR; i++)
        {
            ExtATRBuffer[i] = 0.0;
            firstValue += ExtTRBuffer[i];
        }
        //--- calculating the first value of the indicator
        firstValue /= ExtPeriodATR;
        ExtATRBuffer[ExtPeriodATR] = firstValue;
        limit = ExtPeriodATR + 1;
    }
    else
        limit = prev_calculated - 1;
    //--- the main loop of calculations
    for (i = limit; i < rates_total && !IsStopped(); i++)
    {
        ExtTRBuffer[i] = MathMax(High[i], Close[i - 1]) - MathMin(Low[i], Close[i - 1]);
        ExtATRBuffer[i] = ExtATRBuffer[i - 1] + (ExtTRBuffer[i] - ExtTRBuffer[i - ExtPeriodATR]) / ExtPeriodATR;
    }
    //--- return value of prev_calculated for next call
    return (rates_total);
}
//+------------------------------------------------------------------+

int OnInit()
{
    Sleep(1000); // Sleep for 1000 milliseconds (1 second)

    // Read input parameters from global variables
    int localHMA_Period = (int)GlobalVariableGet(gvPeriod);
    double localHMA_Divisor = GlobalVariableGet(gvDivisor);
    ENUM_APPLIED_PRICE localHMA_Price = (ENUM_APPLIED_PRICE)(int)GlobalVariableGet(gvPrice);
    // Add this line in the main EA's OnInit() function
    ATR_OnInit();

    iHull.init(localHMA_Period, localHMA_Divisor);
    // Your EA OnInit() code
    // Set global variables for HMA input parameters
    GlobalVariableSet("gvHMA_Period", HMA_Period);
    GlobalVariableSet("gvHMA_Divisor", HMA_Divisor);
    GlobalVariableSet("gvHMA_Price", (double)HMA_Price);

    return (INIT_SUCCEEDED);
}

void OnTick()
{
    // Add this code in the main EA's OnTick() function
    int rates_total = Bars(_Symbol, _Period);
    int prev_calculated = 0;
    datetime Time[];
    double Open[], High[], Low[], Close[];
    int Spread[];
    long RealVolume[], TickVolume[];

    CopyTime(_Symbol, _Period, 0, rates_total, Time);
    CopyOpen(_Symbol, _Period, 0, rates_total, Open);
    CopyHigh(_Symbol, _Period, 0, rates_total, High);
    CopyLow(_Symbol, _Period, 0, rates_total, Low);
    CopyClose(_Symbol, _Period, 0, rates_total, Close);
    CopyTickVolume(_Symbol, _Period, 0, rates_total, TickVolume);
    CopyRealVolume(_Symbol, _Period, 0, rates_total, RealVolume);
    CopySpread(_Symbol, _Period, 0, rates_total, Spread);

    int atr_data_calculated = ATR_OnCalculate(rates_total, prev_calculated, Time, Open, High, Low, Close, TickVolume, RealVolume, Spread);

    // Use the ATR value to adjust your stop loss
    double currentATR = ExtATRBuffer[rates_total - 1];
    double stopLossATRMultiplier = 2; // Set the stop loss to be 2 times the ATR value away from the current price

    double closeArray[2];
    if (CopyClose(_Symbol, _Period, 0, 2, closeArray) == -1)
    {
        Print("Error copying close prices: ", GetLastError());
        return;
    }
    double currentClose = closeArray[0];
    double currentPrice = closeArray[1];

    double hmaArray[2];
    int copied = CopyBuffer(iCustom(_Symbol, _Period, "Hull average 2", HMA_Period, HMA_Divisor, (int)HMA_Price), 0, 0, 2, hmaArray);
    if (copied <= 0)
    {
        Print("Error copying HMA buffer: ", GetLastError());
        return;
    }

    Comment("currentClose: " + currentClose + " CurrentPrice: " + currentPrice + "hullValues: " + hmaArray[0] + " hullValues: " + hmaArray[1]);

    double currentHMA = hmaArray[0];
    double previousHMA = hmaArray[1];

    datetime currentTime = TimeCurrent();

    if (currentTime - lastTradeTime >= (1 * 60 * 60))
    {
        if (currentClose > previousHMA && currentClose <= previousHMA)
        {
            // Place SELL order
            if (!trade.Sell(0.01, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_BID), 0, 0))
            {
                Print("Sell order failed with error ", GetLastError());
            }
            else
            {
                Print("Sell order placed: ticket=", trade.ResultOrder(), " volume=", 0.01, " open price=", SymbolInfoDouble(_Symbol, SYMBOL_BID));
                lastTradeTime = currentTime;
            }
        }
        else if (currentClose < previousHMA && currentPrice >= previousHMA)
        {
            // Place BUY order
            if (!trade.Buy(0.01, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_ASK), 0, 0))
            {
                Print("Buy order failed with error ", GetLastError());
            }
            else
            {
                Print("Buy order placed: ticket=", trade.ResultOrder(), " volume=", 0.01, " open price=", SymbolInfoDouble(_Symbol, SYMBOL_ASK));
                lastTradeTime = currentTime;
            }
        }
    }
    // Update stop loss for open orders
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (ticket != INVALID_HANDLE)
        {
            string symbol = PositionGetString(POSITION_SYMBOL);
            ENUM_POSITION_TYPE positionType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double stopLoss = PositionGetDouble(POSITION_SL);
            datetime positionOpenTime = PositionGetInteger(POSITION_TIME);
            int timeDifference = currentTime - positionOpenTime;

            double atr_multiplier = 0.9; // You can adjust this value to your preference

            if (positionType == POSITION_TYPE_BUY)
            {   
                double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                Print("currentAsk: " + currentAsk);
                double new_stop_loss = currentAsk - atr_multiplier * currentATR;
                Print(new_stop_loss);
                // Update the stop loss only if the new stop loss is higher than the previous stop loss and the current ask price is above the open price
                if (new_stop_loss > stopLoss && currentAsk > openPrice)
                {
                    Print("MODIFY BUY TRIGGERED");
                    trade.PositionModify(ticket, new_stop_loss, PositionGetDouble(POSITION_TP));
                }
            }
            else if (positionType == POSITION_TYPE_SELL)
            {
                double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
                Print("currentBid: " + currentBid);
                double new_stop_loss = currentBid + atr_multiplier * currentATR;
                Print(new_stop_loss);
                // Update the stop loss only if the new stop loss is lower than the previous stop loss and the current bid price is below the open price
                if (new_stop_loss < stopLoss && currentBid < openPrice)
                {
                    Print("MODIFY SELL TRIGGERED");
                    trade.PositionModify(ticket, new_stop_loss, PositionGetDouble(POSITION_TP));
                }
            }
        }
    }


}
