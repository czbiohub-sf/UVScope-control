EESchema Schematic File Version 2
LIBS:power
LIBS:device
LIBS:switches
LIBS:relays
LIBS:motors
LIBS:transistors
LIBS:conn
LIBS:linear
LIBS:regul
LIBS:74xx
LIBS:cmos4000
LIBS:adc-dac
LIBS:memory
LIBS:xilinx
LIBS:microcontrollers
LIBS:dsp
LIBS:microchip
LIBS:analog_switches
LIBS:motorola
LIBS:texas
LIBS:intel
LIBS:audio
LIBS:interface
LIBS:digital-audio
LIBS:philips
LIBS:display
LIBS:cypress
LIBS:siliconi
LIBS:opto
LIBS:atmel
LIBS:contrib
LIBS:valves
EELAYER 25 0
EELAYER END
$Descr A4 11693 8268
encoding utf-8
Sheet 1 1
Title ""
Date ""
Rev ""
Comp ""
Comment1 ""
Comment2 ""
Comment3 ""
Comment4 ""
$EndDescr
$Comp
L DG419 U1
U 1 1 5C194554
P 3050 2750
F 0 "U1" H 3150 2650 50  0000 L CNN
F 1 "DG419" H 3150 2850 50  0000 L CNN
F 2 "Housings_DIP:DIP-8_W7.62mm" H 3050 2750 60  0001 C CNN
F 3 "" H 3050 2750 60  0001 C CNN
	1    3050 2750
	-1   0    0    -1  
$EndComp
Wire Wire Line
	3100 1400 3100 2500
$Comp
L GND #PWR01
U 1 1 5C1946A4
P 3000 3550
F 0 "#PWR01" H 3000 3300 50  0001 C CNN
F 1 "GND" H 3000 3400 50  0000 C CNN
F 2 "" H 3000 3550 50  0001 C CNN
F 3 "" H 3000 3550 50  0001 C CNN
	1    3000 3550
	1    0    0    -1  
$EndComp
Wire Wire Line
	3000 3000 3000 3550
$Comp
L SW_SPDT SW1
U 1 1 5C19477D
P 4150 2650
F 0 "SW1" H 4150 2820 50  0000 C CNN
F 1 "SW_SPDT" H 4150 2450 50  0000 C CNN
F 2 "Connectors_Molex:Molex_MicroLatch-53253-0370_03x2.00mm_Straight" H 4150 2650 50  0001 C CNN
F 3 "" H 4150 2650 50  0001 C CNN
	1    4150 2650
	-1   0    0    1   
$EndComp
$Comp
L Conn_Coaxial ExposureIn1
U 1 1 5C194811
P 3700 3050
F 0 "ExposureIn1" H 3710 3170 50  0000 C CNN
F 1 "Conn_Coaxial" V 3815 3050 50  0000 C CNN
F 2 "Connectors_Molex:Molex_MicroLatch-53253-0270_02x2.00mm_Straight" H 3700 3050 50  0001 C CNN
F 3 "" H 3700 3050 50  0001 C CNN
	1    3700 3050
	0    1    1    0   
$EndComp
$Comp
L Conn_Coaxial Vout1
U 1 1 5C194862
P 4700 2650
F 0 "Vout1" H 4710 2770 50  0000 C CNN
F 1 "Conn_Coaxial" V 4815 2650 50  0000 C CNN
F 2 "Connectors_Molex:Molex_MicroLatch-53253-0270_02x2.00mm_Straight" H 4700 2650 50  0001 C CNN
F 3 "" H 4700 2650 50  0001 C CNN
	1    4700 2650
	1    0    0    -1  
$EndComp
$Comp
L Conn_Coaxial AnalogIn1
U 1 1 5C194967
P 1900 2700
F 0 "AnalogIn1" H 1910 2820 50  0000 C CNN
F 1 "Conn_Coaxial" V 2015 2700 50  0000 C CNN
F 2 "Connectors_Molex:Molex_MicroLatch-53253-0270_02x2.00mm_Straight" H 1900 2700 50  0001 C CNN
F 3 "" H 1900 2700 50  0001 C CNN
	1    1900 2700
	-1   0    0    -1  
$EndComp
Wire Wire Line
	4350 2650 4550 2650
Wire Wire Line
	1900 3350 4700 3350
Wire Wire Line
	4700 3350 4700 2850
Connection ~ 3000 3350
Wire Wire Line
	1900 3350 1900 2900
Wire Wire Line
	3100 3000 3000 3000
Wire Wire Line
	2750 3050 3500 3050
Connection ~ 3000 3050
Wire Wire Line
	2450 2550 2450 2800
Wire Wire Line
	2450 2550 3950 2550
Connection ~ 2450 2700
Wire Wire Line
	3350 2900 3700 2900
Wire Wire Line
	3350 2750 3950 2750
$Comp
L R R1
U 1 1 5C194E83
P 2650 1650
F 0 "R1" V 2730 1650 50  0000 C CNN
F 1 "R" V 2650 1650 50  0000 C CNN
F 2 "Resistors_THT:R_Axial_DIN0309_L9.0mm_D3.2mm_P12.70mm_Horizontal" V 2580 1650 50  0001 C CNN
F 3 "" H 2650 1650 50  0001 C CNN
	1    2650 1650
	1    0    0    -1  
$EndComp
$Comp
L R R2
U 1 1 5C194F56
P 2650 2100
F 0 "R2" V 2730 2100 50  0000 C CNN
F 1 "R" V 2650 2100 50  0000 C CNN
F 2 "Resistors_THT:R_Axial_DIN0309_L9.0mm_D3.2mm_P12.70mm_Horizontal" V 2580 2100 50  0001 C CNN
F 3 "" H 2650 2100 50  0001 C CNN
	1    2650 2100
	1    0    0    -1  
$EndComp
Wire Wire Line
	2650 1800 2650 1950
Wire Wire Line
	2650 1850 3000 1850
Wire Wire Line
	3000 1850 3000 2500
Connection ~ 2650 1850
Wire Wire Line
	2650 1500 3100 1500
Connection ~ 3100 1500
$Comp
L GND #PWR02
U 1 1 5C19523F
P 2650 2250
F 0 "#PWR02" H 2650 2000 50  0001 C CNN
F 1 "GND" H 2650 2100 50  0000 C CNN
F 2 "" H 2650 2250 50  0001 C CNN
F 3 "" H 2650 2250 50  0001 C CNN
	1    2650 2250
	1    0    0    -1  
$EndComp
$Comp
L Conn_01x02 J1
U 1 1 5C48C23C
P 3550 1400
F 0 "J1" H 3550 1500 50  0000 C CNN
F 1 "Conn_01x02" H 3550 1200 50  0000 C CNN
F 2 "Connectors_Molex:Molex_MicroLatch-53253-0270_02x2.00mm_Straight" H 3550 1400 50  0001 C CNN
F 3 "" H 3550 1400 50  0001 C CNN
	1    3550 1400
	1    0    0    -1  
$EndComp
Wire Wire Line
	3100 1400 3350 1400
$Comp
L GND #PWR03
U 1 1 5C48C2CD
P 3300 1650
F 0 "#PWR03" H 3300 1400 50  0001 C CNN
F 1 "GND" H 3300 1500 50  0000 C CNN
F 2 "" H 3300 1650 50  0001 C CNN
F 3 "" H 3300 1650 50  0001 C CNN
	1    3300 1650
	1    0    0    -1  
$EndComp
Wire Wire Line
	3350 1500 3300 1500
Wire Wire Line
	3300 1500 3300 1650
$Comp
L +12V #PWR04
U 1 1 5C48C31D
P 3300 1250
F 0 "#PWR04" H 3300 1100 50  0001 C CNN
F 1 "+12V" H 3300 1390 50  0000 C CNN
F 2 "" H 3300 1250 50  0001 C CNN
F 3 "" H 3300 1250 50  0001 C CNN
	1    3300 1250
	1    0    0    -1  
$EndComp
Wire Wire Line
	3300 1250 3300 1400
Connection ~ 3300 1400
Wire Wire Line
	2050 2700 2450 2700
Wire Wire Line
	2450 2800 2750 2800
Wire Wire Line
	2750 2700 2750 3050
$EndSCHEMATC
