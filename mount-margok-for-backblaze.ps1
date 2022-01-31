# Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
# Unrestricted


#."C:\Program Files (x86)\Dokan\DokanLibrary\sample\mirror\mirror.exe" /d /s -r \\192.168.1.49\Archive /l z

$Folder = 'Z:\'

while ($true) {

	Get-Date
	if (-Not(Test-Path -Path $Folder)) {
    		"Path doesn't exist."
		."C:\Program Files (x86)\Dokan\DokanLibrary\sample\mirror\mirror.exe" /d /s -r \\192.168.1.49\Archive /l z."C:\Program Files (x86)\Dokan\DokanLibrary\sample\mirror\mirror.exe" /d /s -r \\192.168.1.49\Archive /l z
	}
	Start-Sleep -Seconds 5 # 60
}
