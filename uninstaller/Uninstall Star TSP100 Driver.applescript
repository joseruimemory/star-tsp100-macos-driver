-- Uninstall Star TSP100 Driver
--
-- A window for /Library/Printers/rastertostarn/uninstall.sh, so that removing
-- the driver takes two clicks and the usual macOS password prompt instead of
-- a Terminal command. English and Portuguese, after the language of the Mac.
--
-- Two harmless modes, chosen by the environment variable STAR_UNINSTALL_TEST.
-- In both, the script runs with --dry-run: nothing is removed and no password
-- is asked, so they never run anything as administrator.
--   demo   the dialogs wait for a click, to see what the app looks like
--   1      the dialogs answer themselves after a second, for automated checks
-- In these modes only, STAR_UNINSTALL_ENGINE may point at another copy of
-- uninstall.sh (a Mac where the package is not installed, for instance).

property engine : "/Library/Printers/rastertostarn/uninstall.sh"
property appTitle : "Star TSP100 Driver"

on isPortuguese()
	try
		set lang to do shell script "defaults read -g AppleLanguages | sed -n 2p | tr -d ' \",'"
		return lang starts with "pt"
	on error
		return false
	end try
end isPortuguese

-- True when the user chooses okLabel.
on confirm(msg, okLabel, cancelLabel, testing, theTitle)
	if testing then
		display dialog msg with title theTitle buttons {cancelLabel, okLabel} default button okLabel cancel button cancelLabel with icon caution giving up after 1
		return true
	end if
	try
		display dialog msg with title theTitle buttons {cancelLabel, okLabel} default button okLabel cancel button cancelLabel with icon caution
		return true
	on error number -128
		return false
	end try
end confirm

on inform(msg, testing, theTitle)
	if testing then
		display dialog msg with title theTitle buttons {"OK"} default button "OK" with icon note giving up after 1
	else
		display dialog msg with title theTitle buttons {"OK"} default button "OK" with icon note
	end if
end inform

on run
	set mode to system attribute "STAR_UNINSTALL_TEST"
	set testing to mode is "1"
	set harmless to testing or (mode is "demo")
	-- A local copy: a property changed at run time could be saved back into the
	-- app, and the next, real run would then execute that path as administrator.
	set enginePath to engine
	if harmless and (system attribute "STAR_UNINSTALL_ENGINE") is not "" then set enginePath to system attribute "STAR_UNINSTALL_ENGINE"
	set pt to isPortuguese()
	set theTitle to appTitle
	if harmless then
		if pt then
			set theTitle to appTitle & " — demonstração, nada é removido"
		else
			set theTitle to appTitle & " — demonstration, nothing is removed"
		end if
	end if
	
	set hasEngine to (do shell script "[ -x " & quoted form of enginePath & " ] && echo yes || echo no") is "yes"
	if not hasEngine then
		set hasFilter to (do shell script "[ -e /Library/Printers/rastertostarn/rastertostarn ] && echo yes || echo no") is "yes"
		if hasFilter then
			-- An early copy, installed by hand before the driver had an uninstaller.
			if pt then
				inform("Este Mac tem uma cópia antiga do driver, instalada sem o desinstalador." & return & return & "Instale primeiro a versão actual (o instalador substitui a antiga) e abra de novo esta aplicação.", testing, theTitle)
			else
				inform("This Mac has an early copy of the driver, installed without its uninstaller." & return & return & "Install the current version first (the installer replaces the old one), then open this app again.", testing, theTitle)
			end if
			return "installed without uninstaller"
		end if
		if pt then
			inform("O driver da Star TSP100 não está instalado neste Mac.", testing, theTitle)
		else
			inform("The Star TSP100 driver is not installed on this Mac.", testing, theTitle)
		end if
		return "not installed"
	end if
	
	set printerNames to paragraphs of (do shell script quoted form of enginePath & " --list-queues")
	set printerLines to ""
	repeat with p in printerNames
		if (contents of p) is not "" then set printerLines to printerLines & return & "  •  " & (contents of p)
	end repeat
	
	if pt then
		set msg to "Isto remove deste Mac o driver da Star TSP100."
		if printerLines is not "" then set msg to msg & return & return & "As impressoras que o usam deixam de poder imprimir, por isso também são removidas:" & return & printerLines
		set msg to msg & return & return & "A seguir é pedida a palavra-passe de um administrador."
		set okLabel to "Desinstalar"
		set cancelLabel to "Cancelar"
	else
		set msg to "This removes the Star TSP100 driver from this Mac."
		if printerLines is not "" then set msg to msg & return & return & "The printers that use it can no longer print, so they are removed too:" & return & printerLines
		set msg to msg & return & return & "Next you are asked for an administrator password."
		set okLabel to "Uninstall"
		set cancelLabel to "Cancel"
	end if
	if not confirm(msg, okLabel, cancelLabel, testing, theTitle) then return "cancelled"
	
	try
		if harmless then
			set out to do shell script quoted form of enginePath & " --dry-run"
		else
			set out to do shell script quoted form of engine with administrator privileges
		end if
	on error errMsg number errNum
		if errNum is -128 then return "cancelled"
		if pt then
			inform("Não foi possível remover o driver:" & return & return & errMsg, testing, theTitle)
		else
			inform("The driver could not be removed:" & return & return & errMsg, testing, theTitle)
		end if
		return "error: " & errMsg
	end try
	
	if harmless then
		if pt then
			inform("Demonstração: nada foi removido." & return & return & out, testing, theTitle)
		else
			inform("Demonstration: nothing was removed." & return & return & out, testing, theTitle)
		end if
		return out
	end if
	if pt then
		inform("O driver da Star TSP100 foi removido." & return & return & "Para o voltar a pôr, abra outra vez o instalador.", testing, theTitle)
	else
		inform("The Star TSP100 driver has been removed." & return & return & "To put it back, open the installer again.", testing, theTitle)
	end if
	return out
end run
