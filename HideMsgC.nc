#ifndef TEST_COMM_H
#define TEST_COMM_H

#define DATASIZE 20
#define AM_UART_ADDR 0xFFFF

#define SRC_NODE 10
#define DST_NODE 50

#define MAGIC 0xDEADBEEF
#define ENC_KEY 3
#define NXT_N 5
#define DST_N 10

typedef struct CommMsg
{
  uint8_t cmd0; // counter
  uint8_t cmd1; // sequence number
  uint16_t nxt_addr;
  uint16_t dst_addr;
  uint8_t data[DATASIZE];
} CommMsg;

// Active Message type for debugging messages
enum {
  AM_DBGMSG = 30,
  AM_CommMSG = 51
};

#endif
