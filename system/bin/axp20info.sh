#!/system/bin/sh
#
# This BusyBox shell script reads various data from the registers of a
# KrossPower / X-Powers AXP202 power management chip as used by Ainol Novo 7
# tablets. The data is decoded and then displayed in a readable format.
# Root privileges required. Use at your own risk!
# Revision 4, 2012 by Tzul of SlateDroid.com
#
# If you get "invalid register number" errors, try updating your BusyBox!
#
# Arguments (specify in any order or quantity):
#   a   show ADC values and counters
#   b   show ADC control settings
#   c   show charge control settings
#   d   show data buffer / cache registers
#   i   show power input status
#   o   show power output settings
#   s   show startup & shutdown timings
#   t   show thresholds
#   v   show VBUS (USB) settings
#   x   show hex dump of all registers
#   all show everything
#


# init global variables
axp_devpath="/sys/devices/i2c-2/2-0034"
axp_regfile="axp20_reg"
axp_regfile2="axp20_regs"
#axp_maxreg=$((0xBA))
axp_maxreg=$((0xFF))
hexprefix="0x"
horzdiv="-------------------------------------------------------------------------------"


getArrayItem()
{
  # get item with index X (0-based) from an array string
  # busybox / ash doesn't support proper arrays, unfortunately
  # arguments: index, array
  local c i
  c=$(($1))
  _result=""
  for i in $2
  do
    [[ $((c--)) -eq 0 ]] && _result=$i && break
  done
}

axp_read()
{
  # read an 8 bit register
  # arguments: register_number
  local rh r a b
  rh=$(printf "%.2x" $1) && r=$(printf "%d" $hexprefix$rh)
  if [[ $? -ne 0 || $r -gt $axp_maxreg ]]
  then
    echo "ERROR: invalid register number in axp_read: $1 (rh=$rh, r=$r)"
    exit 1
  fi
  echo $rh > $axp_devpath/$axp_regfile
  read rh < $axp_devpath/$axp_regfile
  rh=$hexprefix${rh#*=}
  _regval=$((rh))
  return 0
}

axp_read12()
{
  # read a 12 bit value from two consecutive registers
  # arguments: register_number (use_13_bits)
  local rh r v
  rh=$(printf "%.2x" $1) && r=$(printf "%d" $hexprefix$rh)
  if [[ $? -ne 0 || $r -gt $((axp_maxreg - 1)) ]]
  then
    echo "ERROR: invalid register number in axp_read12: $1"
  fi
  ## old code using axp_read, slower than using axp_regfile2 directly
  # axp_read $((r++))
  # v=$((_regval << 4))
  # axp_read $r
  # _regval=$((v + (_regval & 15)))
  echo $rh > $axp_devpath/$axp_regfile2
  read rh < $axp_devpath/$axp_regfile2
  r=${rh%,*}
  v=${rh#*,}
  r=${r#*=}
  v=${v#*=}
  if [[ -z $2 ]]
  then
    _regval=$(((r << 4) + (v & 15)))
  else
    _regval=$(((r << 5) + (v & 31)))
  fi
  return 0
}

axp_read32()
{
  # read an 8*C bit value from C consecutive registers (default: C=4)
  # arguments: register_number, (register_count)
  local rh rd v c
  c=$(($2))
  [[ $c -lt 1 ]] && c=4
  rh=$(printf "%.2x" $1) && rd=$(printf "%d" $hexprefix$rh)
  if [[ $? -ne 0 || $rd -gt $((axp_maxreg - c + 1)) ]]
  then
    echo "ERROR: invalid register number ($1) or count ($c)"
    exit 1
  fi
  v=0
  while [[ $c -gt 0 ]]
  do
    axp_read $((rd++))
    v=$(((v << 8) + _regval))
    let c--
  done
  _regval=$v
  return 0
}

axp_readhex()
{
  # read consecutive registers and return hex string
  # arguments: register_number, register_count
  local rh rd v c
  c=$(($2))
  [[ $c -lt 1 ]] && c=1
  rh=$(printf "%.2x" $1) && rd=$(printf "%d" $hexprefix$rh)
  if [[ $? -ne 0 || $rd -gt $((axp_maxreg - c + 1)) ]]
  then
    echo "ERROR: invalid register number ($1) or count ($c)"
    exit 1
  fi
  v=""
  while [[ $c -gt 0 ]]
  do
    axp_read $((rd++))
    v=$v$(printf "%.2x " $_regval)
    let c--
  done
  _result=$v
  return 0
}

axp_dumpAllRegs()
{
  # dump all registers as hex values
  local r v c lc
  echo -e "$horzdiv\n| HEX DUMP:\n$horzdiv"
  lc=16
  v="___"
  c=0
  while [[ $c -lt $lc ]]
  do
    v=$v$(printf "_%.2x" $c)
    let c++
  done
  echo $v
  c=$((axp_maxreg + 1))
  r=0
  while [[ $c -gt 0 ]]
  do
    [[ $lc -gt $c ]] && lc=$c
    axp_readhex $r $lc
    echo $(printf "%.2x: $_result" $r)
    r=$((r + lc))
    c=$((c - lc))
  done
}

scaleValue()
{
  # scale an integer value by a given factor, add an offset, then a decimal point
  # arguments: value, factor, offset, decimals, unit 
  local len v i k
  v=$(($1 * $2 + $3))
  len=$((${#v} - $4))
  [[ $len -lt 0 ]] && len=0
  i=${v:0:$len}
  k=${v:$len}
  [[ ! -z $k ]] && k=.$k
  _result=$((i))$k$5
}

axp_rawToTemp()
{
  local len v i
  # transform raw value to degrees Celsius
  v=$(($1 - 1447))
  len=$((${#v} - 1))
  i=${v:0:$len}
  [[ -z $i ]] && i=0
  _result=$i.${v:$len}°C
}

bitToStr()
{
  # get a bit from a value and return it as string (default: 0="no", 1="yes")
  # arguments: value, bit_pos, (str0, str1)
  local v b str0 str1
  v=$(($1))
  b=$(($2))
  str0=$3
  str1=$4
  [[ -z $str0 ]] && str0=no
  [[ -z $str1 ]] && str1=yes
  b=$((v & (1 << b)))
  if [[ $b -gt 0 ]]
  then
    _result=$str1
  else
    _result=$str0
  fi
}

getDataBuffer()
{
  axp_readhex 0x04 12
  [[ $# -gt 0 ]] && echo "Data Buffer / Cache = $_result"
}


getAcinVoltage()
{
  axp_read12 0x56
  scaleValue $_regval 17 0 1 mV
  [[ $# -gt 0 ]] && echo "ACIN Voltage = $_result ($_regval)"
}

getAcinCurrent()
{
  axp_read12 0x58
  scaleValue $_regval 625 0 3 mA
  [[ $# -gt 0 ]] && echo "ACIN Current = $_result ($_regval)"
}

getVbusVoltage()
{
  axp_read12 0x5A
  scaleValue $_regval 17 0 1 mV
  [[ $# -gt 0 ]] && echo "VBUS Voltage = $_result ($_regval)"
}

getVbusCurrent()
{
  axp_read12 0x5C
  scaleValue $_regval 375 0 3 mA
  [[ $# -gt 0 ]] && echo "VBUS Current = $_result ($_regval)"
}

getChipTemp()
{
  axp_read12 0x5E
  axp_rawToTemp $_regval
  [[ $# -gt 0 ]] && echo "Internal Chip Temperature = $_result ($_regval)"
}

getBattTemp()
{
  axp_read12 0x62
  axp_rawToTemp $_regval
  [[ $# -gt 0 ]] && echo "External Battery Temperature = $_result ($_regval)"
}

getGpioVoltage()
{
  # arguments: gpio_index
  local n bias
  n=$(($1 & 1))
  # get GPIO ADC input range setting
  axp_read 0x85
  bitToStr $_regval $n 0 1
  bias=$((_result * 7000))
  # read ADC value
  axp_read12 $((n * 2 + 0x64))
  scaleValue $_regval 5 $bias 1 mV
  [[ $# -gt 1 ]] && echo "GPIO$n voltage = $_result ($_regval)"
}

getBattPower()
{
  axp_read32 0x70 3
  # scaleValue $_regval 11 0 4 mW
  _result=$((_regval * 11 / 10000))mW
  [[ $# -gt 0 ]] && echo "Battery instantaneous power = $_result ($_regval)"
}

getBattVoltage()
{
  axp_read12 0x78
  scaleValue $_regval 11 0 1 mV
  [[ $# -gt 0 ]] && echo "Battery Voltage = $_result ($_regval)"
}

getBattChgCurrent()
{
  axp_read12 0x7A
  scaleValue $_regval 5 0 1 mA
  [[ $# -gt 0 ]] && echo "Battery Charge Current = $_result ($_regval)"
}

getBattDisCurrent()
{
  axp_read12 0x7C 1
  scaleValue $_regval 5 0 1 mA
  [[ $# -gt 0 ]] && echo "Battery Discharge Current = $_result ($_regval)"
}

getIpsOutVoltage()
{
  axp_read12 0x7E
  scaleValue $_regval 14 0 1 mV
  [[ $# -gt 0 ]] && echo "System IPSOUT Voltage = $_result ($_regval)"
}

getChgCoulombCounter()
{
  axp_read32 0xB0
  _result=$_regval
  [[ $# -gt 0 ]] && echo "Charge Coulomb Counter = $_regval"
}

getDisCoulombCounter()
{
  axp_read32 0xB4
  _result=$_regval
  [[ $# -gt 0 ]] && echo "Discharge Coulomb Counter = $_regval"
}

getFuelGauge()
{
  local s p
  axp_read 0xB9
  s=$((_regval >> 7))
  p=$((_regval & 127))
  _result=$p
  [[ $# -gt 0 ]] && echo "Fuel Gauge = ${p}% (suspended = $s)"
  return $s
}

getAdcSampleRate()
{
  axp_read 0x84
  getArrayItem $((_regval >> 6)) "25 50 100 200"
  [[ $# -gt 0 ]] && echo "ADC Sample Rate = ${_result}Hz"
}


dumpPowerInputStatus()
{
  local p u x
  echo -e "$horzdiv\n| POWER INPUT STATUS:\n$horzdiv"
  axp_read 0x00
  bitToStr $_regval 7;  p=$_result
  bitToStr $_regval 6;  u=$_result
  echo -e "ACIN:\t\t present=$p, usable=$u"
  bitToStr $_regval 5;  p=$_result
  bitToStr $_regval 4;  u=$_result
  bitToStr $_regval 3;  x=$_result
  echo -e "VBUS:\t\t present=$p, usable=$u, voltage>V_hold=$x"
  bitToStr $_regval 1;  p=$_result
  bitToStr $_regval 0;  u=$_result
  echo -e "ACIN & VBUS:\t shortCircuit=$p, bootSource=$u"
  bitToStr $_regval 2;  x=$_result
  
  axp_read 0x01
  bitToStr $_regval 5;  p=$_result
  bitToStr $_regval 6;  u=$_result
  echo -e "Battery:\t connected=$p, charging0=$x, charging1=$u"
  bitToStr $_regval 7;  x=$_result
  bitToStr $_regval 3;  p=$_result
  bitToStr $_regval 2;  u=$_result
  echo -e "\t\t activateMode=$p, chargeCurrentLow=$u, overTemperature=$x"
}

dumpVbusSettings()
{
  local x y z
  echo -e "$horzdiv\n| VBUS SETTINGS:\n$horzdiv"

  axp_read 0x02
  bitToStr $_regval 2;  x=$_result
  bitToStr $_regval 1;  y=$_result
  bitToStr $_regval 0;  z=$_result
  echo -e "VBUS OTG:\t valid=$x, sessionAB=$y, sessionEnd=$z"

  axp_read 0x30
  bitToStr $_regval 7;  x=$_result
  bitToStr $_regval 6;  y=$_result
  getArrayItem $((_regval & 3)) "900mA 500mA 100mA unlimited"
  z=$_result
  scaleValue $(((_regval >> 3) & 7)) 1 40 1 V
  echo -e "VBUS-IPSOUT:\t N_VBUSEN_ignore=$x, V_hold_enabled=$y, V_hold=$_result, I_limit=$z"  
  
  axp_read 0x8B
  getArrayItem $(((_regval >> 4) & 3)) "4.0 4.15 4.45 4.55"
  x=${_result}V
  str0="disabled enabled"
  bitToStr $_regval 3 $str0;  y=$_result
  bitToStr $_regval 2 $str0;  z=$_result
  echo -e "VBUS:\t\t V_valid=$x, validDetect=$y, sessionDetect=$z"

  bitToStr $_regval 1 $str0;  x=$_result
  bitToStr $_regval 0 $str0;  y=$_result
  echo -e "VBUS Resistance: charge=$x, discharge=$y"
}

dumpPowerOutputControl()
{
  local reg12 reg25 reg28 x y z str0 str1
  echo -e "$horzdiv\n| POWER OUTPUT CONTROL:\n$horzdiv"
  str0="1.6mV/µs"
  str1="0.8mV/µs"

  axp_read 0x12
  reg12=$_regval
  axp_read 0x25
  reg25=$_regval
  axp_read 0x28
  reg28=$_regval
  
  bitToStr $reg12 4;  x=$_result
  bitToStr $reg25 2;  y=$_result
  bitToStr $reg25 0 $str0 $str1;  z=$_result
  axp_read 0x23
  scaleValue $((_regval & 0x3F)) 25 700 0 mV
  echo -e "DC-DC2:\t\t enabled=$x, voltage=$_result, VRC=$y, VRC_slope=$z"

  bitToStr $reg12 1;  x=$_result
  axp_read 0x27
  scaleValue $((_regval & 0x7F)) 25 700 0 mV
  echo -e "DC-DC3:\t\t enabled=$x, voltage=$_result"
  
  echo -e "LDO1:\t\t always enabled, voltage=??"

  bitToStr $reg12 2;  x=$_result
  scaleValue $((reg28 >> 4)) 1 18 1 V
  echo -e "LDO2:\t\t enabled=$x, voltage=$_result"
  
  bitToStr $reg12 6;  x=$_result
  bitToStr $reg25 3;  y=$_result
  bitToStr $reg25 1 $str0 $str1;  z=$_result
  axp_read 0x29
  bitToStr $_regval 7;  str0=$_result
  scaleValue $((_regval & 0x7F)) 25 700 0 mV
  echo -e "LDO3:\t\t enabled=$x, voltage=$_result, VRC=$y, VRC_slope=$z, LDO3IN_enabled=$str0"

  bitToStr $reg12 3;  x=$_result
  getArrayItem $((reg28 & 0xF)) "1.25 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.5 2.7 2.8 3.0 3.1 3.2 3.3"
  echo -e "LDO4:\t\t enabled=$x, voltage=${_result}V"

  # check if GPIO0 or GPIO1 are set to act as LDO5
  z=""
  axp_read 0x90
  [[ $((_regval & 3)) -eq 3 ]] && z=GPIO0
  axp_read 0x92
  [[ $((_regval & 3)) -eq 3 ]] && z=${z}GPIO1
  [[ -z "$z" ]] && z=no
  
  axp_read 0x91
  scaleValue $((_regval >> 4)) 1 18 1 V
  x=$_result
  getArrayItem $((_regval & 7)) "1.8 2.5 2.8 3.0 3.1 3.3 3.4 3.5"
  y=${_result}V
  echo -e "LDO5:\t\t enabled=$z, voltage=$x"
  bitToStr $reg12 0;  x=$_result
  echo -e "EXTEN:\t\t enabled=$x, V_high_EXTEN/GPIO=$y"
}

dumpChargeControl()
{
  local x y z reg34
  echo -e "$horzdiv\n| CHARGING CONTROL:\n$horzdiv"

  axp_read 0x34
  reg34=$_regval
  
  axp_read 0x32
  bitToStr $_regval 3;  x=$_result
  bitToStr $reg34 4 0 1;  y=$_result
  getArrayItem $(((_regval >> 4) & 3)) "off 1Hz 4Hz on"
  echo -e "CHGLED:\t\t manualControl=$x, manualValue=$_result, autoMode=$y"
  
  axp_read 0x33
  bitToStr $_regval 7;  x=$_result
  getArrayItem $(((_regval >> 5) & 3)) "4.1 4.15 4.2 4.36"
  y=${_result}V
  getArrayItem $(((_regval >> 4) & 1)) "10 15"
  z=${_result}%
  scaleValue $((_regval & 0xF)) 100 300 0 mA
  echo -e "Charging:\t enabled=$x, V_target=$y, I_charge=$_result, I_end=$z"

  scaleValue $((reg34 >> 6)) 10 40 0 min
  x=$_result
  scaleValue $((reg34 & 3)) 2 6 0 h
  echo -e "Timeouts:\t preCharge=$x, ccCharge=$_result"
  
  axp_read 0x35
  bitToStr $_regval 7;  x=$_result
  getArrayItem $(((_regval >> 5) & 3)) "3.1 3.0 3.6 2.5"
  y=${_result}V
  getArrayItem $((_regval & 3)) "50 100 200 400"
  z=${_result}µA
  echo -e "Backup Battery:\t chargeEnabled=$x, V_target=$y, I_charge=$z"
}

dumpStartupShutdown()
{
  local w x y z times
  echo -e "$horzdiv\n| STARTUP & SHUTDOWN SETTINGS:\n$horzdiv"
  delayTimes="128ms 1s 2s 3s"

  axp_read 0x32
  bitToStr $_regval 7;  x=$_result
  bitToStr $_regval 6;  y=$_result
  bitToStr $_regval 2 0 1;  z=$_result
  getArrayItem $((_regval & 3)) "$delayTimes"
  echo -e "AXP202:\t\t disable=$x, batteryMonitoring=$y, disableTiming=$z, shutdownDelay=$_result"
  
  axp_read 0x36
  getArrayItem $((_regval >> 6)) "$delayTimes"
  w=$_result
  scaleValue $(((_regval >> 4) & 3)) 5 10 1 s
  x=$_result
  bitToStr $_regval 3;  y=$_result
  bitToStr $_regval 2 8 64;  z=${_result}ms
  scaleValue $((_regval & 3)) 2 4 0 s
  echo -e "AXP202:\t\t startupTime=$w, longpressTime=$x, shutdownOnLongpress=$y"
  echo -e "AXP202:\t\t PWROK_delay=$z, shutdownTime=$_result"
}

dumpAdcCounters()
{
  local i v p x f
  echo -e "$horzdiv\n| ADC DATA & COUNTERS:\n$horzdiv"
  getAcinVoltage;  v=$_result
  getAcinCurrent;  i=$_result
  echo -e "ACIN:\t\t V=$v, I=$i"
  
  getVbusVoltage;  v=$_result
  getVbusCurrent;  i=$_result
  echo -e "VBUS:\t\t V=$v, I=$i"

  getChipTemp;  v=$_result
  getBattTemp;  i=$_result
  echo -e "Temperature:\t chip=$v, external=$i"
  
  getGpioVoltage 0; v=$_result
  getGpioVoltage 1; i=$_result
  echo -e "GPIO:\t\t GPIO0=$v, GPIO1=$i"
  
  getBattPower;    p=$_result
  getBattVoltage;  v=$_result
  getBattChgCurrent;  i=$_result
  getBattDisCurrent
  echo -e "Battery:\t V=$v, I_charge=$i, I_discharge=$_result, P_discharge=$p"
  
  getIpsOutVoltage
  echo -e "System IPSOUT:\t V=$_result"
  
  getAdcSampleRate
  f=$((_result * 225))
  getChgCoulombCounter;  i=$_result
  getDisCoulombCounter;  v=$_result
  p=$(($i * 2048 / $f))
  x=$(($v * 2048 / $f))
  axp_read 0xB8
  bitToStr $_regval 7
  echo -e "Coulomb Counters: enabled=$_result, charge=$i (${p}mAh), discharge=$v (${x}mAh)"
  
  axp_read 0x05
  v=$((_regval & 0x7F))
  getFuelGauge
  p=$?
  x=$_result
  bitToStr $p 0
  echo -e "Fuel Gauge:\t suspended=$_result, chip=$x%, driver=$v%"
}

dumpThresholds()
{
  local x y z
  echo -e "$horzdiv\n| THRESHOLDS:\n$horzdiv"

  axp_read 0x31
  scaleValue $((_regval & 3)) 1 26 1 V
  echo -e "Power Off:\t V_off=$_result"

  z="56 28672 1 mV"
  axp_read 0x3A
  scaleValue $_regval $z
  x=$_result
  axp_read 0x3B
  scaleValue $_regval $z
  y=$_result
  echo -e "System IPSOUT:\t V_warning1=$x, V_warning2=$y"

  z="128 0 1 mV"
  axp_read 0x38
  scaleValue $_regval $z
  x=$_result
  axp_read 0x39
  scaleValue $_regval $z
  y=$_result
  echo -e "Battery Chg:\t underTemp=$x, overTemp=$y"

  axp_read 0x3C
  scaleValue $_regval $z
  x=$_result
  axp_read 0x3D
  scaleValue $_regval $z
  y=$_result
  echo -e "Battery Dischg:\t underTemp=$x, overTemp=$y"
  
  axp_read 0x86
  x=$((_regval * 8))mV
  axp_read 0x87
  y=$((_regval * 8))mV
  echo -e "GPIO1 IRQ:\t risingEdge=$x, fallingEdge=$y"
}

dumpAdcControl()
{
  local w x y z
  echo -e "$horzdiv\n| ADC CONTROL:\n$horzdiv"
  w="disabled enabled"

  axp_read 0x82
  bitToStr $_regval 7 $w;  x=$_result
  bitToStr $_regval 6 $w
  echo -e "Battery ADC:\t V=$x, I=$_result"
  bitToStr $_regval 5 $w;  x=$_result
  bitToStr $_regval 4 $w
  echo -e "ACIN ADC:\t V=$x, I=$_result"
  bitToStr $_regval 3 $w;  x=$_result
  bitToStr $_regval 2 $w
  echo -e "VBUS ADC:\t V=$x, I=$_result"
  bitToStr $_regval 1 $w;  x=$_result
  bitToStr $_regval 0 $w;  y=$_result
  
  axp_read 0x83
  bitToStr $_regval 7 $w
  echo -e "Other ADC:\t APS=$x, externalTemp(TS)=$y, chipTemp=$_result"
  
  bitToStr $_regval 3 $w;  x=$_result
  bitToStr $_regval 2 $w;  y=$_result
  axp_read 0x85
  w="0-2047.5mV 700-2747.5mV"
  bitToStr $_regval 0 $w;  z=$_result
  bitToStr $_regval 1 $w
  echo -e "GPIO0 ADC:\t $x, range=$z"
  echo -e "GPIO1 ADC:\t $y, range=$_result"

  getAdcSampleRate
  x=${_result}Hz
  scaleValue $(((_regval >> 4) & 3)) 20 20 0 µA
  y=$_result
  bitToStr $_regval 2 batteryTemp externalADC
  z=$_result
  getArrayItem $((_regval & 3)) "disabled whileCharging whileSampling always"
  echo -e "ADC Sample Rate: $x"
  echo -e "TS Pin:\t\t function=$z, I_output=$y $_result"
  
}

dumpEverything()
{
  dumpPowerInputStatus
  dumpVbusSettings
  echo $horzdiv
  getDataBuffer 1
  dumpPowerOutputControl
  dumpChargeControl
  dumpStartupShutdown
  dumpAdcCounters
  dumpThresholds
  dumpAdcControl
}

showHelp()
{
  # print the header comment of this file, without the first line
  i=0
  while read line
  do
    [[ "${line:0:1}" != "#" ]] && break
    [[ $((i++)) -eq 0 ]] && continue
    echo "${line:1}"
  done < $0
  exit 0
}

checkRoot()
{
  if [[ "$USER_ID" -ne 0 && "$USER" != "root" && "$(whoami)" != "root" ]]
  then
    echo "ERROR: super user / root required!"
    exit 1
  fi
  
  if [[ ! -f "$axp_devpath/$axp_regfile" ]]
  then
    echo "ERROR: $axp_devpath/$axp_regfile does not exist!"
    echo "Adjust the variable axp_devpath in this script, if necessary."
    exit 1
  fi
}

[[ $# -eq 0 || "$1" == "-h" ]] && showHelp

checkRoot

while [[ $# -gt 0 ]]
do
  case $1 in
    a) dumpAdcCounters ;;
    b) dumpAdcControl ;;
    c) dumpChargeControl ;;
    d) echo $horzdiv; getDataBuffer 1 ;;
    i) dumpPowerInputStatus ;;
    o) dumpPowerOutputControl ;;
    s) dumpStartupShutdown ;;
    t) dumpThresholds ;;
    v) dumpVbusSettings ;;
    x) axp_dumpAllRegs ;;
    all) dumpEverything ;;
    *) echo "ERROR: unknown argument '$1'" ;;
  esac
  shift
done

echo
#exit 0
