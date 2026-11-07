#!/system/bin/sh
SKIPUNZIP=1

ui_print "- Installing ADB/Fastboot host tools"

unzip -o "$ZIPFILE" 'system/*' -d "$MODPATH" >&2
unzip -o "$ZIPFILE" 'module.prop' -d "$MODPATH" >&2

set_perm_recursive "$MODPATH/system/bin" 0 2000 0755 0755
