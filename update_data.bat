@echo off
rem Regenerates procdata.lua / setdata.lua from ..\Forever. Extra args go to the script (--pull, --repo, --only).
py -3 "%~dp0tools\update_data.py" %*
