Set shell = CreateObject("WScript.Shell")
projectRoot = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
shell.CurrentDirectory = projectRoot
command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & projectRoot & "\Stop-Jarvis.ps1"""
shell.Run command, 0, False
