# i2c

[![Build Status](https://travis-ci.org/hdl-util/i2c.svg?branch=master)](https://travis-ci.org/hdl-util/i2c)

Implementation of Inter-IC (I2C) bus master and slave, covering almost all edge cases

## To-dos

- [ ] Master
    - [x] SCL
        - [x] Clock stretching
        - [x] Clock synchronization (multi-master)
        - [x] Stuck LOW line detection (bus clear via HW reset or Power-On Reset)
    - [x] SDA
        - [x] Transmit
        - [x] Receive
        - [x] Arbitration (multi-master)
    - [x] Port map
- [ ] Slave
    - [ ] SCL
    - [ ] SDA
