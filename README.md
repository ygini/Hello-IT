# Hello-IT
The aim of this project is to provide a meta application usage by IT services to provide a status menu for OS X users with all sort of services inside

![Application Screenshot](/Docs/screenshot.png?raw=true "Hello IT")

## Architecture

The application use plugins located in multiple places to support different functions. Those function are usable by system administrator to configure a custom service menu with differents feature inside.

The plugins are located in:
* The application PlugIns folder for the original one;
* /Library/Application Support/com.github.ygini.Hello-IT/PlugIns;
* ~/Library/Application Support/com.github.ygini.Hello-IT/PlugIns;
and loaded in the same order.

Each plugin can offer only one function identified by the HITPFunctionIdentifier key in the info file. When the Hello IT application start, it reference all bundle path per function identifier.

That mean, if the example.function identifier is provided by a bundle in the application package and an other one in the user home folder, the application will use the one in the application folder.

Bundle are listed at the start of the application but not loaded.

## Configuration

To load a bundle, the system administrator need to provide a config file for the domain com.github.ygini.Hello-IT. It can be dpeloyed via a regular pref file or MDM/MCX settings.

The preference file can overload the name of the menu (to change from Hello IT to anythin you want) and build the content of the menu.

Here is an example of what the Hello IT preferences can look like.

```
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>content</key>
	<array>
		<dict>
			<key>functionIdentifier</key>
			<string>public.title</string>
			<key>settings</key>
			<dict>
				<key>title</key>
				<string>Hello IT default content</string>
			</dict>
		</dict>
		<dict>
			<key>functionIdentifier</key>
			<string>public.submenu</string>
			<key>settings</key>
			<dict>
				<key>content</key>
				<array>
					<dict>
						<key>functionIdentifier</key>
						<string>public.test.http</string>
						<key>settings</key>
						<dict>
							<key>URL</key>
							<string>http://captive.apple.com</string>
							<key>mode</key>
							<string>md5</string>
							<key>originalString</key>
							<string>73a78ff5bd7e5e88aa445826d4d6eecb</string>
							<key>repeat</key>
							<integer>60</integer>
							<key>title</key>
							<string>Internet</string>
						</dict>
					</dict>
				</array>
				<key>title</key>
				<string>Services state</string>
			</dict>
		</dict>
		<dict>
			<key>functionIdentifier</key>
			<string>public.separator</string>
		</dict>
		<dict>
			<key>functionIdentifier</key>
			<string>public.open.resource</string>
			<key>settings</key>
			<dict>
				<key>URL</key>
				<string>https://www.apple.com</string>
				<key>title</key>
				<string>Apple</string>
			</dict>
		</dict>
		<dict>
			<key>functionIdentifier</key>
			<string>public.separator</string>
		</dict>
		<dict>
			<key>functionIdentifier</key>
			<string>public.quit</string>
		</dict>
	</array>
	<key>title</key>
	<string>Hello IT</string>
</dict>
</plist>
```

The title key give the name of the menu in the status bar.

Inside content, the array describe the content of menu in the display order (from top to down). Each menu item is defined by a dictionnary who must have the key functionIdentifier and who may have a key settings.

The content of the settings key is a dictionary. Acceptable values for this dictionary can be discovered in the plugin documentation.

The main menu (the root one, that user see in the first time) is loaded by the public.submenu plugin. If you want to use your own plugin to load it, you just have to specify a functionIdentifier at the root of the preferences.

When the main menu is created, the whole user preferences are used as settings. So you can get your own custom preferences if you decide to use a custom submenu plugin.
