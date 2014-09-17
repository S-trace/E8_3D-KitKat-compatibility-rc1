#!/system/bin/sh
#
# This BusyBox shell script changes specific settings of a
# KrossPower / X-Powers AXP202 power management chip as used by Ainol Novo 7
# tablets.
# Root privileges required. Use at your own risk!
# Revision 3, 2012 by Tzul of SlateDroid.com
#
# If you get "invalid register number" errors, try updating your BusyBox!
#
# Arguments (specify in any order and quantity):
#   I_limit <value>   set VBUS (USB) current limit to <value> mA
#   V_target <value>  set battery charging target voltage to <value> V
#   I_charge <value>  set battery charging current to <value> mA
#   I_end <value>     set battery charging end current to <value> % of I_charge
#   C_clear           reset charge and discharge Coulomb counters to 0
#


# init global variables
axp_devpath="/sys/devices/i2c-2/2-0034"
axp_regfile="axp20_reg"
#axp_maxreg=$((0xBA))
axp_maxreg=$((0xFF))
hexprefix="0x"



getArrayIndexOf()
{
  # get index (0-based) of a given item in a given array string
  # arguments: item, array, raise_error_if_not_found
  local i c
  _result=""
  c=0
  for i in $2
  do
    [[ "$i" == "$1" ]] && _result=$c && break
    let c++
  done
  if [[ -z "$_result" && $(($3)) -ne 0 ]]
  then
    echo "ERROR: invalid value \"$1\". Supported: $2"
    exit 1
  fi
}


axp_read()
{
  # read an 8 bit register
  # arguments: register_number
  local rh r
  rh=$(printf "%.2x" $1) && r=$(printf "%d" $hexprefix$rh)
  if [[ $? -ne 0 || $r -gt $axp_maxreg ]]
  then
    echo "ERROR: invalid register number in axp_read: $1 (max=$axp_maxreg)"
    exit 1
  fi
  echo $rh > $axp_devpath/$axp_regfile
  read rh < $axp_devpath/$axp_regfile
  rh=$hexprefix${rh#*=}
  _regval=$((rh))
  return 0
}

axp_write()
{
  # write an 8 bit register
  # arguments: register_number value
  local rh r vh v
  rh=$(printf "%.2x" $1) && r=$(printf "%d" $hexprefix$rh)
  if [[ $? -ne 0 || $r -gt $axp_maxreg ]]
  then
    echo "ERROR: invalid register number in axp_write: $1 (max=$axp_maxreg)"
    exit 1
  fi
  vh=$(printf "%.2x" $2) && v=$(printf "%d" $hexprefix$vh)
  if [[ $v -lt 0 || $v -gt 255 ]]
  then
    echo "ERROR: invalid 8 bit value: $v"
    exit 1
  fi
  #echo $rh > $axp_devpath/$axp_regfile
  echo $rh$vh > $axp_devpath/$axp_regfile
  return 0
}


setVbusCurrentLimit()
{
  echo "setting VBUS current limit to $1 mA"
  local reg v values
  reg=0x30
  values="900 500 100 unlimited"
  getArrayIndexOf $1 "$values" 1
  v=$((_result & 3))
  axp_read $reg
  v=$(((_regval & 0xFC) | v))
  axp_write $reg $v
}

setBattTargetVoltage()
{
  echo "setting battery charging target voltage to $1 V"
  local reg v values
  reg=0x33
  # 4.36V is dangerous, better don't use it
  # values="4.1 4.15 4.2 4.36"
  values="4.1 4.15 4.2"
  getArrayIndexOf $1 "$values" 1
  v=$((_result & 3))
  axp_read $reg
  v=$(((_regval & 0x9F) | (v << 5)))
  axp_write $reg $v
}

setBattChargeCurrent()
{
  echo "setting battery charging current to $1 mA"
  local reg v values
  reg=0x33
  values="300 400 500 600 700 800 900 1000 1100 1200 1300 1400 1500 1600 1700 1800"
  getArrayIndexOf $1 "$values" 1
  v=$((_result & 0xF))
  axp_read $reg
  v=$(((_regval & 0xF0) | v))
  axp_write $reg $v
}

setBattChargeEnd()
{
  echo "setting battery charging end current to $1% of I_charge"
  local reg v values
  reg=0x33
  values="10 15"
  getArrayIndexOf $1 "$values" 1
  v=$((_result & 1))
  axp_read $reg
  v=$(((_regval & 0xEF) | (v << 4)))
  axp_write $reg $v
}

clearCoulombCounters()
{
  echo "clearing Coulomb counters"
  local reg v
  reg=0xB8
  axp_read $reg
  v=$((_regval | (1 << 5)))
  axp_write $reg $v
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
  opCount=2
  case $1 in
    I_limit)  setVbusCurrentLimit $2 ;;
    V_target) setBattTargetVoltage $2 ;;
    I_end)    setBattChargeEnd $2 ;; 
    I_charge) setBattChargeCurrent $2 ;;
    C_clear)  clearCoulombCounters; opCount=1 ;;
    *) echo "ERROR: unknown argument '$1 $2'" ;;
  esac
  shift $opCount
done

echo
#exit 0
