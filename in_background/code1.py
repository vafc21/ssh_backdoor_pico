# code.py — tiny launcher: run D:\run_task.ps1; the script self-elevates & does everything in background
import time
import usb_hid
from adafruit_hid.keyboard import Keyboard
from adafruit_hid.keycode import Keycode
from adafruit_hid.keyboard_layout_us import KeyboardLayoutUS

kbd = Keyboard(usb_hid.devices)
layout = KeyboardLayoutUS(kbd)

def type_and_enter(s, delay=0.6):
    layout.write(s)
    kbd.send(Keycode.ENTER)
    time.sleep(delay)

time.sleep(5)                 # give Windows time to be ready
kbd.send(Keycode.WINDOWS, Keycode.R)
time.sleep(2.0)               # ensure Run box is focused

# VERY short, no-Admin one-liner; the PS1 will self-elevate hidden
cmd = r'powershell -w hidden -nop -ep bypass -file D:\run_task.ps1'
type_and_enter(cmd, delay=0.3)
time.sleep(2)
kbd.send(Keycode.LEFT_ARROW, Keycode.ENTER)

while True:
    time.sleep(1)