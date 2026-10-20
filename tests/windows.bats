#!/usr/bin/env bats

# shellcheck disable=SC2317,SC2329 # the stubs are called by the code under test
load helpers

setup() { load_dudu; fake_windows; }

@test "Git Bash, MSYS and Cygwin are windows" {
  [ "$(dudu_os)" = windows ]
  is_windows
  run ! is_macos
  run ! is_linux
  uname() { echo MSYS_NT-10.0; }
  [ "$(dudu_os)" = windows ]
  uname() { echo CYGWIN_NT-10.0; }
  [ "$(dudu_os)" = windows ]
}

@test "macOS and Linux are not windows" {
  uname() { echo Darwin; }
  run ! is_windows
  uname() { echo Linux; }
  run ! is_windows
  [ "$(dudu_os)" = linux ]
}

@test "win_reg reads one value, without the CR" {
  REG_ProductName="Windows 10 Pro"
  [ "$(win_reg 'HKLM\SOFTWARE\X' ProductName)" = "Windows 10 Pro" ]
  run ! test -n "$(win_reg 'HKLM\SOFTWARE\X' Missing)"
}

@test "os_pretty says Windows 11 for builds from 22000" {
  REG_ProductName="Windows 10 Pro" REG_CurrentBuild=26100
  [ "$(os_pretty)" = "Windows 11 Pro" ]
  REG_CurrentBuild=19045
  [ "$(os_pretty)" = "Windows 10 Pro" ]
  REG_ProductName="" REG_CurrentBuild=""
  [ "$(os_pretty)" = "Windows" ]
}

@test "dudu_host is COMPUTERNAME" {
  COMPUTERNAME="DEV-PC 01"
  [ "$(dudu_host)" = "DEV-PC01" ]
}

@test "machine_id comes from MachineGuid" {
  REG_MachineGuid=aaaa-bbbb
  a=$(machine_id)
  REG_MachineGuid=cccc-dddd
  b=$(machine_id)
  [ "$a" != "$b" ]
  [ ${#a} -eq 12 ]
}

@test "the Windows locale picks the language when LANG says nothing" {
  unset LANGUAGE LC_ALL LC_MESSAGES LANG
  REG_LocaleName=pt-BR
  [ "$(i18n_system_language)" = pt-BR ]
  REG_LocaleName=es-MX
  [ "$(i18n_system_language)" = es ]
}

@test "AppData folders default under HOME" {
  unset APPDATA LOCALAPPDATA
  [ "$(win_appdata)" = "$HOME/AppData/Roaming" ]
  [ "$(win_localappdata)" = "$HOME/AppData/Local" ]
}

@test "as_root does not use sudo on Windows" {
  run as_root echo hi
  [ "$output" = hi ]
}
