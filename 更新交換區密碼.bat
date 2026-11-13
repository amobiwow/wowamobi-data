@echo off
chcp 65001 >nul
echo 更新家裡這台記住的交換區密碼（公司電腦的 fileshare 帳號）
echo.
echo 請輸入剛剛在公司電腦設定的新密碼（打字時畫面不會顯示），打完按 Enter。
cmdkey /add:192.168.0.109 /user:DESKTOP-6B5T2KM\fileshare /pass
echo.
echo 好了，這個視窗可以關掉。
pause
