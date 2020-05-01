#include "HideMsg.h"

// configuration
configuration HideMsgC
{}

// implementation
implementation
{
    // use these components
  components MainC, HideMsgM, LedsC, RandomC;
  // Timers
  components new TimerMilliC() as Timer0;
  components new TimerMilliC() as RelayTimer;
  components new TimerMilliC() as DbgTimer;

  // Radio
  components new AMSenderC(AM_CommMSG);
  components new AMReceiverC(AM_CommMSG);
  components ActiveMessageC as Radio;

  // Serial
  components new SerialAMSenderC(AM_DBGMSG);
  components SerialActiveMessageC as Serial;


  // wire up module
  MainC.Boot <- HideMsgM.Boot;
  HideMsgM.AMControl -> Radio;
  HideMsgM.SerialControl -> Serial;
  
  HideMsgM.RadioSend -> AMSenderC.AMSend;
  HideMsgM.Receive -> AMReceiverC;
  HideMsgM.RadioPacket -> AMSenderC;

  HideMsgM.SerialSend -> SerialAMSenderC.AMSend;

  // wire up LEDs
  HideMsgM.Leds -> LedsC;

  // wire up PRNG
  HideMsgM.Random -> RandomC;

  // wire up timers
  HideMsgM.Timer0 -> Timer0;
  HideMsgM.RelayTimer -> RelayTimer;
  HideMsgM.DbgTimer -> DbgTimer;
}
