' 悬浮窗启动器(插件 SessionStart hook 调用;相对自身定位,无需绝对路径)
' NoShowIfExists:已有悬浮窗在运行时不打扰(不弹到前台),没有则静默拉起
Dim dir, shell
dir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
Set shell = CreateObject("WScript.Shell")
shell.Run "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "\glm-usage-widget.ps1"" -NoShowIfExists", 0, False
