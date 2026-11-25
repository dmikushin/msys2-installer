// Generated product settings (mkinstaller fills this in).
var PRODUCT = @PRODUCT_JSON@;

function cancelInstaller(message)
{
    installer.setDefaultPageVisible(QInstaller.Introduction, false);
    installer.setDefaultPageVisible(QInstaller.TargetDirectory, false);
    installer.setDefaultPageVisible(QInstaller.ComponentSelection, false);
    installer.setDefaultPageVisible(QInstaller.ReadyForInstallation, false);
    installer.setDefaultPageVisible(QInstaller.StartMenuSelection, false);
    installer.setDefaultPageVisible(QInstaller.PerformInstallation, false);
    installer.setDefaultPageVisible(QInstaller.LicenseCheck, false);

    var abortText = "<font color='red'>" + message +"</font>";
    installer.setValue("FinishedText", abortText);
    installer.setValue("RunProgram", null);
}

function isSupported()
{
    if (systemInfo.kernelType === "winnt") {
        var major = parseInt(systemInfo.kernelVersion.split(".", 1));
        var minor = parseInt(systemInfo.kernelVersion.split(".", 2)[1]);
        // Windows >= 8.1
        if (major > 6 || (major == 6 && minor >= 3)) {
            return true;
        }
    }
    return false;
}

// The licence key file: given on the command line as LicenseKeyFile=<path>,
// or chosen on the "Licence key" page of the GUI.
function licenseKeyFile()
{
    var key = installer.value("LicenseKeyFile", "");
    if (key === "" && PRODUCT.channel && installer.isInstaller()) {
        var page = gui.pageWidgetByObjectName("DynamicLicenseKeyPage");
        if (page != null) {
            key = page.keyPath.text;
        }
    }
    return key;
}

function createShortcuts()
{
    var windir = installer.environmentVariable("WINDIR");
    if (windir === "") {
        QMessageBox["warning"]( "Error" , "Error", "Could not find windows installation directory");
        return;
    }

    var launcher = "@TargetDir@/" + PRODUCT.launcher + ".exe";
    var icon = "iconPath=@TargetDir@/" + PRODUCT.launcher + ".ico";
    component.addOperation("CreateShortcut", launcher, "@StartMenuDir@/" + PRODUCT.terminalName + ".lnk", icon);
    if (PRODUCT.desktopShortcut) {
        component.addOperation("CreateShortcut", launcher, "@DesktopDir@/" + PRODUCT.terminalName + ".lnk", icon);
    }
}

function installLicenseKey()
{
    if (!PRODUCT.channel) {
        return;
    }
    var key = licenseKeyFile();
    if (key === "") {
        console.log("No licence key given: updates from " + PRODUCT.channel.remote + " stay disabled until " +
                    PRODUCT.channel.keyPath + " is installed.");
        return;
    }
    component.addOperation("Mkdir", "@TargetDir@/" + PRODUCT.channel.keyDir);
    component.addOperation("Copy", key, "@TargetDir@/" + PRODUCT.channel.keyPath);
}

function firstRun()
{
    // First login shell: /etc/post-install initialises the pacman keyring.
    component.addOperation("Execute",
                           ["@TargetDir@\\usr\\bin\\bash.exe", "--login", "-c", "exit"]);
    // Install the bundled product packages with the target's own pacman.
    component.addOperation("Execute",
                           ["@TargetDir@\\usr\\bin\\bash.exe", "--login", "-c", PRODUCT.firstRun]);
}

function Component() {

    if (!isSupported()) {
        cancelInstaller("Installation on " + systemInfo.prettyProductName + " is not supported");
        return;
    }

    // Names the Windows "Apps & features" entry; must not collide with other products.
    installer.setValue("ProductUUID", PRODUCT.id);

    if (PRODUCT.channel && installer.isInstaller()) {
        installer.addWizardPage(component, "LicenseKeyPage", QInstaller.StartMenuSelection);
        var page = gui.pageWidgetByObjectName("DynamicLicenseKeyPage");
        if (page != null) {
            page.browseButton.clicked.connect(function() {
                var path = QFileDialog.getOpenFileName("Licence key", page.keyPath.text, "*");
                if (path !== "") {
                    page.keyPath.text = path;
                }
            });
        }
    }
}

Component.prototype.createOperations = function()
{
    component.createOperations();
    installLicenseKey();
    createShortcuts();
    firstRun();
}
