@echo off
echo Deploying Lunara Backend to IIS Server...

REM Build the application
echo Building application...
npm run build

REM Copy dist files to server
echo Copying dist files to server...
xcopy /E /I /Y "D:\Softwares\Lunara_backend\server\dist" "\\103.224.247.22\C$\inetpub\wwwroot\lunara-backend\dist"

REM Copy web.config to server
echo Copying web.config to server...
copy "D:\Softwares\Lunara_backend\server\web.config" "\\103.224.247.22\C$\inetpub\wwwroot\lunara-backend\"

REM Copy package.json for dependencies
echo Copying package.json to server...
copy "D:\Softwares\Lunara_backend\server\package.json" "\\103.224.247.22\C$\inetpub\wwwroot\lunara-backend\"

REM Copy .env file
echo Copying .env to server...
copy "D:\Softwares\Lunara_backend\server\.env" "\\103.224.247.22\C$\inetpub\wwwroot\lunara-backend\"

echo Deployment complete!
echo Please restart IIS site on the server.
pause