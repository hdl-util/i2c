# i2c

[![Build Status](https://travis-ci.org/hdl-util/i2c.svg?branch=master)](https://travis-ci.org/hdl-util/i2c)

Implementation of Inter-IC (I2C) bus master and slave, covering almost all edge cases

## To-dos

- Master
    - [x] SCL
        - [x] Clock stretching
        - [x] Clock synchronization (multi-master)
            - [ ] Handle early counter reset
        - [x] Stuck LOW line detection (bus clear via HW reset or Power-On Reset)
        - [x] Release line when bus is free / in use by another master
        - [x] Conformity to stop/repeated start setup & hold times
    - [x] SDA
        - [x] Transmit
        - [x] Receive
        - [x] Arbitration (multi-master)
            - [x] Basic Implementation
            - [x] Detect other masters triggering start before this master
        - [ ] Hotloading (not from i2c spec)
            - [ ] Self
                - compensating for jitter of wires connecting/disconnecting... (Schmitt enough?)
                - listen for WAIT_TIME_END to see if the clock is driven LOW
                - if no: bus is free
                - if yes: keep listening until a STOP or START
            - [x] Other masters
                - [x] erroneous starts detected w/ start_err
    - [x] Port map
- Slave
    - [ ] SCL
    - [ ] SDA
- Speeds
    - [x] Standard-mode
    - [x] Fast-mode
    - [x] Fast-mode Plus
    - [ ] High-speed mode
    - [ ] Ultra Fast-mode


## Reference Documents

- [I2C Specification](https://www.nxp.com/docs/en/user-guide/UM10204.pdf)
- [Understanding the I2C Bus](http://www.ti.com/lit/an/slva704/slva704.pdf)
