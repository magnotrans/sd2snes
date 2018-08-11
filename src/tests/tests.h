/* ___DISCLAIMER___ */

#ifndef _TESTS_H
#define _TESTS_H

#define LOGPRINT(...) {printf(__VA_ARGS__); f_printf(&logfile, __VA_ARGS__);}

int test_sd(void);
int test_rtc(void);
int test_cic(void);
int test_fpga(void);
int test_mem(void);
int test_clk(void);
int test_sddma(void);

enum tests { TEST_SD = 0,
             TEST_USB,
             TEST_RTC,
             TEST_CIC,
             TEST_FPGA,
             TEST_RAM,
             TEST_SDDMA,
             TEST_CLK,
             TEST_DAC,
             TEST_SNES_IRQ,
             TEST_SNES_RAM,
             TEST_SNES_PA };

enum teststates { NO_RUN = 0, PASSED, FAILED };

#endif
