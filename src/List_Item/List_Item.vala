/* window.vala
 *
 * Copyright 2021 Erik Reider
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

namespace SwaySettings {
    [GtkTemplate (ui = "/org/erikreider/swaysettings/List_Item/List_Item.ui")]
    public class List_Item : Gtk.ListBoxRow {

        public static unowned int height_req = 70;

        [GtkChild]
        public unowned Gtk.Label label;
        [GtkChild]
        unowned Gtk.Box box;

        public List_Item (string title, Gtk.Widget widget) {
            Object ();
            label.label = title;
            box.add (widget);
            widget.halign = Gtk.Align.FILL;
            widget.hexpand = true;
            this.height_request = 70;
        }
    }

    public class List_Slider : List_Item {
        Gtk.Scale slider_widget;

        public delegate bool on_release_delegate (Gdk.EventButton event_button, Gtk.Scale slider);

        public List_Slider (string title, double min, double max, double step, on_release_delegate on_release) {
            var slider_widget = new Gtk.Scale.with_range (Gtk.Orientation.HORIZONTAL, min, max, step);
            slider_widget.button_release_event.connect ((event) => on_release (event, slider_widget));
            base (title, slider_widget);

            this.slider_widget = slider_widget;
        }

        public void set_value (float value) {
            slider_widget.set_value (value);
        }
    }

    public class List_Switch : List_Item {
        Gtk.Switch switch_widget;

        public delegate bool on_state_set (bool state);

        public List_Switch (string title, on_state_set on_release) {
            var switch_widget = new Gtk.Switch ();
            switch_widget.state_set.connect ((value) => on_release (value));
            base (title, switch_widget);
            switch_widget.halign = Gtk.Align.END;
            switch_widget.valign = Gtk.Align.CENTER;

            this.switch_widget = switch_widget;
        }

        public void set_active (bool value) {
            switch_widget.set_active (value);
        }
    }

    public class List_Combo_Enum : Hdy.ComboRow {

        public delegate void selected_index ();

        public List_Combo_Enum (string title, GLib.Type enum_type, selected_index callback) {
            Object ();

            this.set_title (title);
            this.height_request = List_Item.height_req;
            this.selectable = false;

            this.set_for_enum (enum_type, (val) => {
                var nick = val.get_nick ();
                return nick.up (1) + nick.slice (1, nick.length);
            });
            this.notify["selected-index"].connect ((e) => callback ());
        }

        public void set_selected_from_enum (int val) {
            int selected_index = 0;
            for (int i = 0; i < this.get_model ().get_n_items (); i++) {
                if (val == i) selected_index = i;
            }
            this.set_selected_index (selected_index);
        }
    }

    public class List_Lazy_Image : Gtk.Box {

        public string image_path;

        public Gtk.Image image;

        public List_Lazy_Image (string image_path, int requested_height, int requested_width) {
            Object ();
            this.image_path = image_path;

            this.valign = Gtk.Align.CENTER;
            this.halign = Gtk.Align.CENTER;
            this.set_margin_start (8);
            this.set_margin_top (8);
            this.set_margin_end (8);
            this.set_margin_bottom (8);

            image = new Gtk.Image ();
            image.set_size_request (requested_width, requested_height);
            this.add (image);
            this.show_all ();

            var thread_func = new Image_Load_Thread (image_path, ref image, requested_width, requested_height);
            new Thread<void>(image_path, thread_func.run);
        }

        class Image_Load_Thread {

            private string path;
            private int img_w;
            private int img_h;
            private Gtk.Image image;

            public Image_Load_Thread (string path, ref Gtk.Image image, int img_w, int img_h) {
                this.path = path;
                this.image = image;
                this.img_w = img_w;
                this.img_h = img_h;
            }

            public void run () {
                Functions.scale_image_widget (ref image, path, img_w, img_h);
            }
        }
    }
}
