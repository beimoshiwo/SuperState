#!/bin/sh
# SuperState 管理员模式启动脚本：以全新会话常驻 powermetrics
/usr/bin/pkill -x powermetrics 2>/dev/null
sleep 0.4

/usr/bin/python3 - <<'PYEOF'
import subprocess
p = subprocess.Popen(
    ["/usr/bin/powermetrics", "-n", "-1", "-i", "1000",
     "-s", "cpu_power,gpu_power,thermal,smc",
     "-o", "/tmp/superstate_powermetrics.log"],
    stdin=subprocess.DEVNULL,
    stdout=open("/dev/null", "wb"),
    stderr=subprocess.STDOUT,
    start_new_session=True)   # setsid：脱离调用者会话，被 launchd 收养
with open("/tmp/superstate_pm.pid", "w") as f:
    f.write(str(p.pid))
PYEOF
