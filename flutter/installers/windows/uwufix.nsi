; uwuFix's Windows installer, uwufix-<version>-setup.exe (docs/flutter-desktop-app-spec.md §10):
;
; - per user, no administrator needed, asking where to install (default
;   %LOCALAPPDATA%\Programs\uwuFix, or wherever an earlier install went);
; - x64 and Arm64 in one installer, picking the computer's own;
; - closes a running copy first, clears the folder, installs, and writes "Uninstall uwuFix.exe"
;   beside the app (the updater tells this install apart by it, lib/desktop/updater.dart);
; - Start menu and desktop shortcuts, and the uwu:// scheme (the app registers it again at every
;   start, links_desktop.dart);
; - /S installs silently, as the app's updater runs it, with --updated and --force-run to start
;   the app afterwards.
;
; Built by .github/workflows/build-desktop.yml:
;   makensis /DVERSION=1.1.0 /DX64=<x64 Release folder> [/DARM64=<arm64 Release folder>] /DOUT=<file> uwufix.nsi

Unicode true
ManifestDPIAware true
RequestExecutionLevel user
SetCompressor /SOLID lzma

!include "MUI2.nsh"
!include "x64.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"

!ifndef VERSION
  !define VERSION "0.0.0"
!endif
!ifndef OUT
  !define OUT "uwufix-${VERSION}-setup.exe"
!endif

!define APP "uwuFix"
!define APPID "org.uwuapps.fixup"
!define EXECUTABLE "uwuFix.exe"
!define UNINSTALLER "Uninstall uwuFix.exe"
; Where Windows' "Installed apps" list reads the app's entry from.
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPID}"
; Where this install's folder is remembered, for the next install to go to.
!define LOCATION_KEY "Software\UwU Apps\uwuFix"

Name "${APP}"
OutFile "${OUT}"
InstallDir "$LOCALAPPDATA\Programs\${APP}"
InstallDirRegKey HKCU "${LOCATION_KEY}" "InstallLocation"
BrandingText "${APP} ${VERSION}"
VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "${APP}"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "FileDescription" "${APP} installer"
VIAddVersionKey "CompanyName" "UwU Apps"
VIAddVersionKey "LegalCopyright" "Augy, UwU Apps. MIT licence."

!define MUI_ICON "..\..\windows\runner\resources\app_icon.ico"
!define MUI_UNICON "..\..\windows\runner\resources\app_icon.ico"
!define MUI_FINISHPAGE_RUN "$INSTDIR\${EXECUTABLE}"
!define MUI_FINISHPAGE_RUN_TEXT "Open ${APP}"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Var ForceRun
Var Parameters
Var ForceRunOption
Var InstalledSize
Var FileCount
Var FolderCount
Var UrlCommand

Function .onInit
  ; The updater's arguments, as an Electron updater passes them.
  ${GetParameters} $Parameters
  ${GetOptions} $Parameters "--force-run" $ForceRunOption
  ${IfNot} ${Errors}
    StrCpy $ForceRun "1"
  ${EndIf}
FunctionEnd

; A running copy is closed first, or its files can't be replaced.
!macro CloseRunning
  nsExec::Exec 'taskkill /IM "${EXECUTABLE}" /F'
  Sleep 800
!macroend

Section "Install"
  !insertmacro CloseRunning
  ; Whatever was here before goes, so nothing of an older build is left behind.
  RMDir /r "$INSTDIR"
  SetOutPath "$INSTDIR"
!ifdef ARM64
  ${If} ${IsNativeARM64}
    File /r "${ARM64}\*.*"
  ${Else}
    File /r "${X64}\*.*"
  ${EndIf}
!else
  File /r "${X64}\*.*"
!endif

  WriteUninstaller "$INSTDIR\${UNINSTALLER}"

  CreateShortCut "$SMPROGRAMS\${APP}.lnk" "$INSTDIR\${EXECUTABLE}" "" "$INSTDIR\${EXECUTABLE}" 0
  ${IfNot} ${Silent}
    CreateShortCut "$DESKTOP\${APP}.lnk" "$INSTDIR\${EXECUTABLE}" "" "$INSTDIR\${EXECUTABLE}" 0
  ${EndIf}

  ; uwu://fix links.
  WriteRegStr HKCU "Software\Classes\uwu" "" "URL:uwu"
  WriteRegStr HKCU "Software\Classes\uwu" "URL Protocol" ""
  WriteRegStr HKCU "Software\Classes\uwu\shell\open\command" "" '"$INSTDIR\${EXECUTABLE}" "%1"'

  WriteRegStr HKCU "${LOCATION_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayName" "${APP}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "Publisher" "UwU Apps"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\${EXECUTABLE}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" '"$INSTDIR\${UNINSTALLER}"'
  WriteRegStr HKCU "${UNINSTALL_KEY}" "QuietUninstallString" '"$INSTDIR\${UNINSTALLER}" /S'
  WriteRegStr HKCU "${UNINSTALL_KEY}" "URLInfoAbout" "https://fixup.uwuapps.org"
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1
  ${GetSize} "$INSTDIR" "/S=0K" $InstalledSize $FileCount $FolderCount
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "EstimatedSize" $InstalledSize

  ; Silent, from the app's updater: open the new version straight away.
  ${If} ${Silent}
  ${AndIf} $ForceRun == "1"
    Exec '"$INSTDIR\${EXECUTABLE}"'
  ${EndIf}
SectionEnd

Section "Uninstall"
  !insertmacro CloseRunning
  Delete "$SMPROGRAMS\${APP}.lnk"
  Delete "$DESKTOP\${APP}.lnk"
  ; The uwu:// scheme goes only if it still opens this install.
  ReadRegStr $UrlCommand HKCU "Software\Classes\uwu\shell\open\command" ""
  ${If} $UrlCommand == '"$INSTDIR\${EXECUTABLE}" "%1"'
    DeleteRegKey HKCU "Software\Classes\uwu"
  ${EndIf}
  ; The app's start at sign-in (launch_at_startup's Run value).
  DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "${APP}"
  DeleteRegKey HKCU "${UNINSTALL_KEY}"
  DeleteRegKey HKCU "${LOCATION_KEY}"
  RMDir /r "$INSTDIR"
SectionEnd
