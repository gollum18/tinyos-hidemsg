#include "HideMsg.h"
#include "AM.h"
#include "Serial.h"
#include "Timer.h"

module HideMsgM @safe() {
  uses {
    interface Boot;
    interface SplitControl as AMControl;
    interface SplitControl as SerialControl;

    interface AMSend as RadioSend;
    interface Receive;
    interface Packet as RadioPacket;

    interface AMSend as SerialSend;

    interface Timer<TMilli> as Timer0;
    interface Timer<TMilli> as RelayTimer;
    interface Timer<TMilli> as DbgTimer;

    interface Leds;
    interface Random;
  }
}

implementation {
  uint8_t message[DATASIZE];

  message_t rdo_envelope;
  message_t fwd_envelope;
  message_t rcv_envelope;
  message_t dbg_envelope;

  CommMsg *rdo_msg;
  CommMsg *dbg_msg;
  CommMsg *fwd_msg;
  CommMsg *rcv_msg;

  bool locked;
  uint8_t counter;

  uint32_t before;
  uint32_t after;
  uint32_t interval;

  uint16_t get_nexthop(uint16_t dst) {
    if (dst > TOS_NODE_ID) 
      return TOS_NODE_ID + 10;
    else if (dst < TOS_NODE_ID) 
      return TOS_NODE_ID - 10;

    return 0xffff;
  }

  void generate_random(uint16_t * pkey, uint16_t nwords) {
    uint8_t i;
    uint16_t num;

    for (i = 0; i < nwords; i++) {
      num = call Random.rand16();
      pkey[i] = 0x00ff & num;
      num = call Random.rand16();
      pkey[i] |= ((0x00ff & num) << 8);
    }
  }

  /**
   * Encrypts a uint16_t value.
   * @param k The encryption key.
   * @param v The value to encrypt.
   * @param n The multiplier.
   * @returns The encrypted form of v.
   */
  uint16_t encrypt16(uint16_t k, uint16_t v, uint16_t n) {
    uint16_t e = v;

    e = e * n;
    e = e ^ (k * n);

    return e;
  }

  /**
   * Decrypts a uint16_t value.
   * @param k The encryption key.
   * @param e The encrypted value.
   * @param n The multiplier.
   * @returns The decrypted form of n.
   */
  uint16_t decrypt16(uint16_t k, uint16_t e, uint16_t n) {
    uint16_t v = e;

    v = v ^ (k * n);
    v = v / n;

    return v;
  }

  void mod_data(uint8_t data[], uint8_t size, uint32_t magic) {
    uint8_t i = 0;
      
    for (; i < size; i += 8) {
       atomic {
        data[i] = data[i] ^ MAGIC;
        data[i+1] = data[i+1] ^ (MAGIC >> 4);
        data[i+2] = data[i+2] ^ (MAGIC >> 8);
        data[i+3] = data[i+3] ^ (MAGIC >> 12);
        data[i+4] = data[i+4] ^ (MAGIC >> 16);
        data[i+5] = data[i+5] ^ (MAGIC >> 20);
        data[i+6] = data[i+6] ^ (MAGIC >> 24);
        data[i+7] = data[i+7] ^ (MAGIC >> 28);
      }
    }
  }

  ////////////////////////////////////////////////////////////////////////
  // tasks
  ////////////////////////////////////////////////////////////////////////
  
  task void send_uart_msg() {
      uint8_t len;
      len = call RadioPacket.payloadLength(&fwd_envelope);
      if (call SerialSend.send(AM_UART_ADDR, &fwd_envelope, len) != SUCCESS)
        post send_uart_msg();
  }

  /**
   * Initialize module.
   */
  event void Boot.booted() {
    call AMControl.start();

    rdo_msg = (CommMsg *)rdo_envelope.data;
    fwd_msg = (CommMsg *)fwd_envelope.data;
    dbg_msg = (CommMsg *)dbg_envelope.data;
    rcv_msg = (CommMsg *)rcv_envelope.data;
    
    counter = 0;

    call SerialControl.start();
  }

  event void AMControl.startDone(error_t error) {
    if (error == SUCCESS) {
      if (TOS_NODE_ID == SRC_NODE) 
        call Timer0.startPeriodic(1000);
    }
    else {
      call AMControl.start();
    }
  }

  event void SerialControl.startDone(error_t error) {}
  event void SerialControl.stopDone(error_t error) {}
  event void AMControl.stopDone(error_t error) {}

  event void DbgTimer.fired() {
    //call SerialSend.send(0xffff, &dbg_envelope, uart_len);
    post send_uart_msg();
  }

  event void RelayTimer.fired() {    
    uint16_t next_node = 0;

    if (locked) return;
    else {
       rcv_msg = (CommMsg *) call RadioPacket.getPayload(&rcv_envelope, sizeof(CommMsg));
    }
    if (rcv_msg == NULL) return;

    next_node = get_nexthop(rcv_msg->dst_addr);

    fwd_msg = (CommMsg *) call RadioPacket.getPayload(&fwd_envelope, sizeof(CommMsg));
    memcpy(fwd_msg, rcv_msg, sizeof(CommMsg));
    fwd_msg->nxt_addr = encrypt16(ENC_KEY, next_node, NXT_N);
    fwd_msg->dst_addr = encrypt16(ENC_KEY, fwd_msg->dst_addr, DST_N);
    fwd_msg->cmd0 = rcv_msg->cmd0 + 1;

    if (call RadioSend.send(AM_BROADCAST_ADDR, &fwd_envelope, sizeof(CommMsg)) == SUCCESS) {
      locked = TRUE;
    }
  }

  event void Timer0.fired() {
    counter++;
    before = call Timer0.getNow();
    interval = before;
    generate_random((uint16_t *)message, DATASIZE/2);
    
    //memcpy(&(dbg_msg->saddr), (uint8_t *)&interval, 4);

    if (locked) return;
    else
      rdo_msg = (CommMsg *) call RadioPacket.getPayload(&rdo_envelope, sizeof(CommMsg));

    if (rdo_msg == NULL) return;

    memset(rdo_msg, 0, sizeof(CommMsg));
    rdo_msg->cmd1 = counter;
    rdo_msg->nxt_addr = encrypt16(ENC_KEY, 20, NXT_N);
    rdo_msg->dst_addr = encrypt16(ENC_KEY, DST_NODE, DST_N);
    mod_data(rdo_msg->data, DATASIZE, MAGIC);
    memcpy(rdo_msg->data, (uint8_t *)message, DATASIZE);

    if (call RadioSend.send(AM_BROADCAST_ADDR, &rdo_envelope, sizeof(CommMsg)) == SUCCESS) {
      locked = TRUE;
    }
  }

  event void RadioSend.sendDone(message_t *m, error_t error) {
    if (m == &rdo_envelope) {
      call Leds.led1Toggle();
      locked = FALSE;
    } else if (m == &fwd_envelope) {
      call Leds.led2Toggle();
      locked = FALSE;
    } else {
      call Leds.led0Toggle();
    }
  }

  event void SerialSend.sendDone(message_t *m, error_t error) {
  }

  event message_t* Receive.receive(message_t *msg,
                                        void *payload,
					uint8_t len){
    CommMsg *rcvmsg = (CommMsg *)msg->data;

    rcvmsg->nxt_addr = decrypt16(ENC_KEY, rcvmsg->nxt_addr, NXT_N);
    rcvmsg->dst_addr = decrypt16(ENC_KEY, rcvmsg->dst_addr, DST_N);
    if (TOS_NODE_ID == DST_NODE) {
        mod_data(rcvmsg->data, DATASIZE, MAGIC);
    }

    if (TOS_NODE_ID == rcvmsg->nxt_addr) {
      memcpy(&dbg_envelope, msg, sizeof(message_t));
      call DbgTimer.startOneShot(500);
      if (TOS_NODE_ID < rcvmsg->dst_addr) {
        memcpy(&rcv_envelope, msg, sizeof(message_t));
        call RelayTimer.startOneShot(200);
      } 
    }

    return msg;
  }
}
