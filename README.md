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
        - [ ] Arbitration (multi-master)
            - [x] Basic Implementation
            - [ ] Detect slower masters changing the value by looking at the value exactly at negedge(scl)
    - [x] Port map
- [ ] Slave
    - [ ] SCL
    - [ ] SDA
