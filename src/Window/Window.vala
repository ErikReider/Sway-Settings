using Gee;

namespace SwaySettings {
    public enum PageType {
        WALLPAPER,
        APPEARANCE,
        STARTUP_APPS,
        DEFAULT_APPS,
        SWAYNC,
        SOUND,
        BLUETOOTH,
        KEYBOARD,
        MOUSE,
        TRACKPAD,
        USERS;

        public string ? get_name () {
            switch (this) {
                case WALLPAPER:
                    return "Wallpaper";
                case APPEARANCE:
                    return "Appearance";
                case STARTUP_APPS:
                    return "Startup Apps";
                case DEFAULT_APPS:
                    return "Default Apps";
                case SWAYNC:
                    return "Sway Notification Center";
                case BLUETOOTH:
                    return "Bluetooth";
                case SOUND:
                    return "Sound";
                case KEYBOARD:
                    return "Keyboard";
                case MOUSE:
                    return "Mouse";
                case TRACKPAD:
                    return "Trackpad";
                case USERS:
                    return "Users";
            }
            return null;
        }

        public string ? get_internal_name () {
            switch (this) {
                case WALLPAPER:
                    return "wallpaper";
                case APPEARANCE:
                    return "appearance";
                case STARTUP_APPS:
                    return "startup-apps";
                case DEFAULT_APPS:
                    return "default-apps";
                case SWAYNC:
                    return "swaync";
                case BLUETOOTH:
                    return "bluetooth";
                case SOUND:
                    return "sound";
                case KEYBOARD:
                    return "keyboard";
                case MOUSE:
                    return "mouse";
                case TRACKPAD:
                    return "trackpad";
                case USERS:
                    return "users";
            }
            return null;
        }
    }

    [GtkTemplate (ui = "/org/erikreider/swaysettings/Window/Window.ui")]
    public class Window : Hdy.ApplicationWindow {
        [GtkChild]
        unowned Hdy.Deck deck;
        [GtkChild]
        unowned Gtk.Box content_box;
        [GtkChild]
        unowned Gtk.Box page_box;

        private Item[] items = {};
        private string ? current_page_name = null;
        private Gtk.GestureMultiPress gesture;

        private IPC ipc;

        public void navigato_to_page (string page) {
            if (current_page_name != null
                && current_page_name == page
                && deck.visible_child_name != "main_page") return;
            foreach (var item in items) {
                if (item == null) continue;
                if (item.settings_item.internal_name == page) {
                    item.activate ();
                    break;
                }
            }
        }

        public Window (Gtk.Application app) {
            Object (application: app);
            ipc = new IPC ();

            // Only call the page `on_back` method when done transitioning
            deck.notify.connect ((o, p) => {
                if (p.name != "transition-running"
                    && p.name != "visible-child-name") return;
                if (!deck.transition_running
                    && deck.visible_child_name == "main_page") {
                    if (page_box.get_children ().is_empty ()) return;
                    Gtk.Widget child = page_box.get_children ().first ().data;
                    if (child is Page) {
                        Page page = ((Page) child);
                        page.on_back.begin (deck);
                    }
                }
            });
            deck.notify["visible-child-name"].connect (() => {
                if (page_box.get_children ().is_empty ()) return;
                Gtk.Widget child = page_box.get_children ().first ().data;
                if (child is Page) {
                    Page page = ((Page) child);
                    if (deck.visible_child_name == "main_page") {
                        page.set_reveal_child (false);
                    } else {
                        page.set_reveal_child (true);
                    }
                }
            });

            gesture = new Gtk.GestureMultiPress (this);
            gesture.set_button (8);
            gesture.set_propagation_phase (Gtk.PropagationPhase.CAPTURE);
            gesture.pressed.connect ((g, n, x, y) => {
                deck.navigate (Hdy.NavigationDirection.BACK);
            });

            SettingsCategory[] items = {
                SettingsCategory ("Desktop", {
                    SettingsItem ("preferences-desktop-wallpaper", PageType.WALLPAPER, "wallpaper"),
                    SettingsItem ("preferences-desktop-theme", PageType.APPEARANCE, "appearance"),

                    SettingsItem ("applications-other", PageType.STARTUP_APPS, "startup-apps"),
                    SettingsItem ("preferences-other", PageType.DEFAULT_APPS, "default-apps"),
                    // SettingsItem ("mail-unread", PageType.SWAYNC, "swaync", !Functions.is_swaync_installed ()),
                }),
                SettingsCategory ("Hardware", {
                    SettingsItem ("bluetooth-symbolic", PageType.BLUETOOTH, "bluetooth"),
                    SettingsItem ("audio-speakers-symbolic", PageType.SOUND, "sound"),
                    SettingsItem ("input-keyboard", PageType.KEYBOARD, "keyboard"),
                    SettingsItem ("input-mouse", PageType.MOUSE, "mouse"),
                    SettingsItem ("input-touchpad", PageType.TRACKPAD, "trackpad"),
                }),
                SettingsCategory ("Administration", {
                    SettingsItem ("system-users", PageType.USERS, "users"),
                }),
            };

            for (int index = 0; index < items.length; index++) {
                var category = items[index];
                var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
                if (index % 2 != 0) box.get_style_context ().add_class ("view");

                var title = new Gtk.Label (category.title);
                Pango.AttrList li = new Pango.AttrList ();
                li.insert (Pango.attr_weight_new (Pango.Weight.BOLD));
                li.insert (new Pango.AttrSize (12288));
                title.set_attributes (li);

                title.xalign = 0.0f;
                int margin = 8;
                title.set_margin_top (margin);
                title.set_margin_start (margin);
                title.set_margin_bottom (2);
                title.set_margin_end (margin);

                var flow_box = new Gtk.FlowBox () {
                    homogeneous = true,
                    vexpand = false,
                    min_children_per_line = 3,
                    max_children_per_line = 7,
                    selection_mode = Gtk.SelectionMode.NONE,
                };
                flow_box.child_activated.connect ((child) => {
                    foreach (var c in page_box.get_children ()) {
                        if (c != null) page_box.remove (c);
                    }
                    Item item = (Item) child;
                    if (item == null) return;
                    current_page_name = item.settings_item.internal_name;
                    Page ? page = get_page (item.settings_item);
                    if (page == null) return;
                    page_box.add (page);
                    deck.navigate (Hdy.NavigationDirection.FORWARD);
                });
                foreach (var settings_item in category.items) {
                    if (settings_item.hidden) continue;
                    string ? name = settings_item.page_type.get_internal_name ();
                    if (name == null) continue;
                    var item = new Item (settings_item);
                    this.items += item;
                    flow_box.add (item);
                }
                if (flow_box.get_children ().length () <= 0) continue;

                box.add (title);
                box.add (flow_box);
                content_box.add (box);
            }

            content_box.show_all ();
        }

        public Page ? get_page (SettingsItem item) {
            switch (item.page_type) {
                case WALLPAPER:
                    return new Background_Page (item, deck, ipc);
                case APPEARANCE:
                    return new Themes_Page (item, deck);
                case STARTUP_APPS:
                    return new Startup_Apps (item, deck);
                case DEFAULT_APPS:
                    return new Default_Apps (item, deck);
                case SWAYNC:
                    return new Swaync (item, deck, ipc);
                case BLUETOOTH:
                    return new Bluetooth_Page (item, deck);
                case SOUND:
                    return new Pulse_Page (item, deck);
                case KEYBOARD:
                    return new Keyboard_Page (item, deck, ipc);
                case MOUSE:
                    return new Mouse_Page (item, deck, ipc);
                case TRACKPAD:
                    return new Trackpad_Page (item, deck, ipc);
                case USERS:
                    return new Users (item, deck);
            }
            return null;
        }
    }

    struct SettingsCategory {
        string title;
        SettingsItem[] items;

        public SettingsCategory (string title, SettingsItem[] items) {
            this.title = title;
            this.items = items;
        }
    }

    public struct SettingsItem {
        string image;
        bool hidden;
        PageType page_type;

        string internal_name;
        string name;

        SettingsItem (string image,
                      PageType page_type,
                      string internal_name,
                      bool hidden = false) {
            this.image = image;
            this.page_type = page_type;
            this.hidden = hidden;

            this.internal_name = page_type.get_internal_name ();
            this.name = page_type.get_name ();
        }
    }
}
