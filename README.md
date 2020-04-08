# i2c

[![Build Status](https://travis-ci.com/hdl-util/i2c.svg?branch=master)](https://travis-ci.com/hdl-util/i2c)

SystemVerilog code for [I2C](https://en.wikipedia.org/wiki/I%C2%B2C) master/slave on an [FPGA](https://simple.wikipedia.org/wiki/Field-programmable_gate_array).

## Usage


1. Take files from `src/` and add them to your own project. If you use [hdlmake](https://hdlmake.readthedocs.io/en/master/), you can add this repository itself as a remote module.
1. Other helpful modules are also available in this GitHub organization.
1. Consult the usage example in [i2c-demo](https://github.com/hdl-util/i2c-demo) for code that runs a demo over HDMI.
1. Read through the parameters in `i2c_master.sv`/`i2c_slave.sv` and tailor any instantiations to your situation.
1. Please create an issue if you run into a problem or have any questions.

### To-do List

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
        - [x] Arbitration (multi-master) (untested)
            - [x] Basic Implementation
            - [x] Detect other masters triggering start before this master
        - [ ] Hotloading (not from i2c spec)
            - [ ] Self
                - compensating for jitter of wires connecting/disconnecting... (Schmitt enough?)
                - listen for WAIT_TIME_END to see if the clock is driven LOW
                - if no: bus is free
                - if yes: keep listening until a STOP or START
            - [x] Other masters (untested)
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
- [ ] MIPI I3C


## Reference Documents

These documents are not hosted here! They are available on Library Genesis and at other locations.

- [I2C Specification](https://www.nxp.com/docs/en/user-guide/UM10204.pdf)
- [Understanding the I2C Bus](http://www.ti.com/lit/an/slva704/slva704.pdf)
- [MIPI I3C Specification](https://b-ok.cc/book/3710131/fc48ef)
