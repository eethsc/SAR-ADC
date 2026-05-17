# Clock (125 MHz)
set_property -dict { PACKAGE_PIN K17   IOSTANDARD LVCMOS33 } [get_ports { sysclk }]

set_property -dict { PACKAGE_PIN W15   IOSTANDARD LVCMOS33 } [get_ports { comp_out }];

# LEDs (ST3 시각화)
set_property -dict { PACKAGE_PIN M14   IOSTANDARD LVCMOS33 } [get_ports { led_st3 }]

# Pmod Header JC (ST1 관찰용)
set_property -dict { PACKAGE_PIN V15   IOSTANDARD LVCMOS33 } [get_ports { pmod_st1 }]

# Pmod Header JD (dac0 ~ dac3)
set_property -dict { PACKAGE_PIN T14   IOSTANDARD LVCMOS33 } [get_ports { pmod_dac0 }]
set_property -dict { PACKAGE_PIN T15   IOSTANDARD LVCMOS33 } [get_ports { pmod_dac1 }]
set_property -dict { PACKAGE_PIN P14   IOSTANDARD LVCMOS33 } [get_ports { pmod_dac2 }]
set_property -dict { PACKAGE_PIN R14   IOSTANDARD LVCMOS33 } [get_ports { pmod_dac3 }]

# Pmod Header JE (dac4 ~ dac7)
set_property -dict { PACKAGE_PIN V12   IOSTANDARD LVCMOS33 } [get_ports { pmod_dac4 }]
set_property -dict { PACKAGE_PIN W16   IOSTANDARD LVCMOS33 } [get_ports { pmod_dac5 }]
set_property -dict { PACKAGE_PIN J15   IOSTANDARD LVCMOS33 } [get_ports { pmod_dac6 }]
set_property -dict { PACKAGE_PIN H15   IOSTANDARD LVCMOS33 } [get_ports { pmod_dac7 }]