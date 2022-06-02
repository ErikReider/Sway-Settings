using Gee;

namespace SwaySettings {
    public class Mouse_Page : Input_Page {

        public Mouse_Page (SettingsItem item, Hdy.Deck deck, IPC ipc) {
            base (item, deck, ipc);
        }

        public override SwaySettings.Input_Types input_type {
            get {
                return Input_Types.POINTER;
            }
        }

        public override Input_Page_Option get_options () {
            return new Input_Page_Option (new ArrayList<Gtk.Widget>.wrap ({
                get_scroll_factor (),
                get_natural_scroll (),
                get_accel_profile (),
                get_pointer_accel (),
            }), "General");
        }
    }
}
