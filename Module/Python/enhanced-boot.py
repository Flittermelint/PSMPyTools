# This file is executed on every boot (including wake-boot from deepsleep)
#import esp
#esp.osdebug(None)
#import webrepl
#webrepl.start()
#---------------------------------------------------------------------------------------------------
import machine
import sys
#---------------------------------------------------------------------------------------------------
def restart(Soft=False):
    if Soft:
        machine.soft_reset()
    else:
        machine.reset()
#---------------------------------------------------------------------------------------------------
print("-"*80)
print("Python Version: %s" % sys.version)
#---------------------------------------------------------------------------------------------------
try:
    import lvgl as lv
    print("LVGL   Version: %d.%d.%d" % (lv.version_major(), lv.version_minor(), lv.version_patch()))
except:
    pass
#---------------------------------------------------------------------------------------------------
print("-"*80)
#---------------------------------------------------------------------------------------------------
