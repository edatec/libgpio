#!/bin/bash

unset -f is_positive_integer    >/dev/null 2>&1
unset -f gpio_select_gpiochip   >/dev/null 2>&1
unset -f gpio_gpiochip_isset    >/dev/null 2>&1
unset -f gpio_count             >/dev/null 2>&1
unset -f gpio_exported          >/dev/null 2>&1
unset -f gpio_unexported        >/dev/null 2>&1
unset -f gpio_export_all        >/dev/null 2>&1
unset -f gpio_unexport_all      >/dev/null 2>&1
unset -f gpio_get_edge          >/dev/null 2>&1
unset -f gpio_get_active_low    >/dev/null 2>&1
unset -f gpio_set_active_low    >/dev/null 2>&1
unset -f gpio_get_direction     >/dev/null 2>&1
unset -f gpio_direction_output  >/dev/null 2>&1
unset -f gpio_direction_input   >/dev/null 2>&1
unset -f gpio_get_value         >/dev/null 2>&1
unset -f gpio_set_value         >/dev/null 2>&1

GPIO_SYS="/sys/class/gpio"

die()
{
    echo "$*"
    exit 1
}

is_positive_integer()
{
    local _val="$1"

    if ! echo "$_val" | grep -E '^[0-9]+$' >/dev/null 2>&1; then
        echo "$_val: not a positive integer"
        return 1
    fi

    return 0
}

gpio_gpiochip_update()
{
    local _gpiochip_n="$1"

    if ls /dev/gpiochip${_gpiochip_n} > /dev/null;then
        gpio=$(ls -d /sys/class/gpio/gpiochip*/device/gpiochip0)
        echo "$gpio" | sed -n 's|/sys/class/gpio/gpiochip\([0-9]*\).*|\1|p'
        return 0
    fi

    echo $_gpiochip_n
    return 0
}

gpio_select_gpiochip()
{
    local _gpiochip_n="$1"

    is_positive_integer "$_gpiochip_n" || return 2

    if [ ! -d "$GPIO_SYS" ]; then
        echo "${GPIO_SYS}: directory not found or permission denied"
        echo "The kernel may not be able to support GPIO_SYSFS."
        return 1
    fi

    if [ ! -d "${GPIO_SYS}/gpiochip${_gpiochip_n}" ]; then
        echo "gpiochip${_gpiochip_n}: controller not found"
        return 1
    fi

    GPIOCHIP_N="$_gpiochip_n"
    export GPIOCHIP_N

    return 0
}

gpio_gpiochip_isset()
{
    if ! test -n "$GPIOCHIP_N"; then
        echo "GPIOCHIP_N: variable not set"
        return 1
    fi

    if [ "$GPIOCHIP_N" -lt 0 ]; then
        echo "GPIOCHIP_N: must be a positive integer"
        return 1
    fi

    return 0
}

gpio_count()
{
    gpio_gpiochip_isset || return 3

    ngpio_path="${GPIO_SYS}/gpiochip${GPIOCHIP_N}/ngpio"

    if ! cat "$ngpio_path" 2>/dev/null; then
        echo "gpio_count() failed"
        return 1
    fi
    return 0
}

gpio_export()
{
    local _gpio_id="$1"

    is_positive_integer "$_gpio_id" || return 2

    gpio_gpiochip_isset || return 3

    gpio_n=$((GPIOCHIP_N + _gpio_id))

    if ! echo "$gpio_n" > "${GPIO_SYS}/export" 2>/dev/null; then
        if [ ! -d "${GPIO_SYS}/gpio${gpio_n}" ]; then
            echo "gpio$gpio_n: gpio_export() failed"
            return 1
        fi
    fi

    return 0
}

gpio_unexport()
{
    local _gpio_id="$1"

    is_positive_integer "$_gpio_id" || return 2

    gpio_gpiochip_isset || return 3

    gpio_n=$((GPIOCHIP_N + _gpio_id))

    if ! echo "$gpio_n" > "${GPIO_SYS}/unexport" 2>/dev/null; then
        echo "gpio$gpio_n: gpio_unexport() failed"
        return 1
    fi

    return 0
}

gpio_exported()
{
    local _gpio_id="$1"

    is_positive_integer "$_gpio_id" || return 2

    gpio_gpiochip_isset || return 3

    gpio_n=$((GPIOCHIP_N + _gpio_id))

    test -d "${GPIO_SYS}/gpio${gpio_n}"
}

gpio_unexported()
{
    gpio_exported "$1"
    rc="$?"
    [ "$rc" -eq 1 ] && return 0
    [ "$rc" -eq 0 ] && return 1
    return "$rc"
}

gpio_export_all()
{
    gpio_gpiochip_isset || return 3

    count="$(gpio_count)" || return 1

    if [ "$count" -eq 0 ]; then
        return 0
    fi

    count=$((count - 1))

    for i in $(seq 0 "$count"); do
        gpio_export "$i"
    done

    return 0
}

gpio_unexport_all()
{
    gpio_gpiochip_isset || return 3

    count="$(gpio_count)" || return 1

    if [ "$count" -eq 0 ]; then
        return 0
    fi

    count=$((count - 1))

    for i in $(seq 0 "$count"); do
        gpio_unexport "$i"
    done

    return 0
}

gpio_get_property()
{
    local _gpio_id="$1"
    local _property="$2"

    is_positive_integer "$_gpio_id" || return 2

    case ${_property} in
        value|active_low|edge|direction) ;;
        *) return 2;;
    esac

    gpio_gpiochip_isset || return 3
    gpio_exported "$_gpio_id" || return 1

    gpio_n=$((GPIOCHIP_N + _gpio_id))

    if ! cat "${GPIO_SYS}/gpio${gpio_n}/${_property}" 2>/dev/null; then
        echo "gpio${_gpio_id}: gpio_get_${_property}() failed"
        return 1
    fi

    return 0
}

gpio_set_property()
{
    local _gpio_id="$1"
    local _property="$2"
    local _val="$3"

    is_positive_integer "$_gpio_id" || return 2

    case ${_property} in
        value|active_low) is_positive_integer "$_val" || return 2;;
        direction)
            if ! echo "$_val" | grep -E '^(in|out)$' >/dev/null 2>&1; then
                return 2
            fi
            ;;
        *) return 2;;
    esac

    gpio_gpiochip_isset || return 3
    gpio_exported "$_gpio_id" || return 1

    gpio_n=$((GPIOCHIP_N + _gpio_id))

    if ! echo "$_val" > "${GPIO_SYS}/gpio${gpio_n}/${_property}" 2>/dev/null
    then
        echo "gpio${_gpio_id}: gpio_set_${_property}() failed"
        return 1
    fi

    return 0
}

gpio_get_edge()
{
    gpio_get_property "$1" "edge"
}

gpio_get_active_low()
{
    gpio_get_property "$1" "active_low"
}

gpio_set_active_low()
{
    gpio_set_property "$1" "active_low" "$2"
}

gpio_get_direction()
{
    gpio_get_property "$1" "direction"
}

gpio_direction_input()
{
    gpio_set_property "$1" "direction" "in"
}

gpio_direction_output()
{
    gpio_set_property "$1" "direction" "out"
}

gpio_get_value()
{
    gpio_get_property "$1" "value"
}

gpio_set_value()
{
    gpio_set_property "$1" "value" "$2"
}

set_gpio()
{
    local _gpiochip_n=$1
    local _gpio_id=$2
    local _gpio_value=$3

    gpio_select_gpiochip ${_gpiochip_n}
    gpio_gpiochip_isset || return $?

    gpio_exported $_gpio_id
    if [ $? -ne 0 ];then
        gpio_export $_gpio_id || return $?
    fi
    
    gpio_direction_output $_gpio_id
    gpio_set_value $_gpio_id $_gpio_value
}

get_gpio()
{
    local _gpiochip_n=$1
    local _gpio_id=$2

    gpio_select_gpiochip ${_gpiochip_n}
    gpio_gpiochip_isset || return $?

    gpio_exported $_gpio_id
    if [ $? -ne 0 ];then
        gpio_export $_gpio_id || return $?
    fi
    
    gpio_get_value $_gpio_id
}

find_gpio()
{
    local _gpio_name=$1
    which gpiofind > /dev/null
    if [ $? -eq 0 ];then
        gpiofind "$_gpio_name"
    else
        cat /sys/kernel/debug/gpio | grep "$_gpio_name"
    fi
}

usage()
{
    echo "Usage: $0 get <chip name/number> <offset 1> <offset 2> ..."
    echo "Read line value(s) from a GPIO chip."
    echo 
    echo "Usage: $0 set <chip name/number> <offset1>=<value1> <offset2>=<value2> ..."
    echo "Set GPIO line values of a GPIO chip."
    echo 
    echo "Usage: $0 find <name>"
    echo "Find a GPIO line by name."
    echo 
    echo "Uasge: $0 help"
    echo "Display this help and exit."
}

main()
{
    local opt=$1
    
    case "${opt}" in 
        set|get)
            local gpiochip=$(gpio_gpiochip_update $2)
            if [ "${opt}" = set ];then
                local set_values="${@:3}"
                for set_value in ${set_values[@]};do
                    local gpio_id=${set_value%%=*}
                    local gpio_value=${set_value#*=}
                    set_gpio ${gpiochip} ${gpio_id} ${gpio_value}
                done
            else
                # get
                local gpio_ids="${@:3}"
                for gpio_id in ${gpio_ids[@]};do
                    get_gpio ${gpiochip} ${gpio_id}
                done
            fi
            ;;
        find)
            local gpio_name=$2
            find_gpio "$gpio_name"
            ;;
        help|*)
            usage
            ;;
    esac
}

main $*
