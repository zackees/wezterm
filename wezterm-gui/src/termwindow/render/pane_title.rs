use crate::quad::TripleLayerQuadAllocator;
use crate::tabbar::parse_status_text;
use crate::termwindow::render::RenderScreenLineParams;
use crate::termwindow::{UIItem, UIItemType};
use config::TabBarColors;
use mlua::FromLua;
use mux::renderable::RenderableDimensions;
use mux::tab::PositionedPane;
use std::time::{Duration, Instant};
use termwiz::cell::Cell;
use termwiz::cell::CellAttributes;
use termwiz::surface::SEQ_ZERO;
use termwiz_funcs::{format_as_escapes, FormatItem};
use wezterm_term::color::ColorAttribute;
use wezterm_term::Line;
use window::color::LinearRgba;

pub(crate) struct PaneTitleCacheEntry {
    text: String,
    expires: Instant,
    width: usize,
    is_active: bool,
    terminal_title: String,
}

impl PaneTitleCacheEntry {
    fn valid(&self, now: Instant, width: usize, is_active: bool, terminal_title: &str) -> bool {
        self.expires > now
            && self.width == width
            && self.is_active == is_active
            && self.terminal_title == terminal_title
    }
}

fn title_from_lua(value: mlua::Value, lua: &mlua::Lua) -> anyhow::Result<Option<String>> {
    match value {
        mlua::Value::Nil => Ok(None),
        mlua::Value::Table(_) => {
            let items = Vec::<FormatItem>::from_lua(value, lua)?;
            Ok(Some(format_as_escapes(items)?))
        }
        _ => Ok(Some(String::from_lua(value, lua)?)),
    }
}

fn format_pane_title(pos: &PositionedPane, config: &config::ConfigHandle) -> String {
    let info = crate::TermWindow::pos_pane_to_pane_info(pos);
    let formatted = config::run_immediate_with_lua_config(|lua| {
        if let Some(lua) = lua {
            let value = config::lua::emit_sync_callback(
                &*lua,
                (
                    "format-pane-title".to_string(),
                    (info, (**config).clone(), pos.width),
                ),
            )?;
            title_from_lua(value, &lua)
        } else {
            Ok(None)
        }
    });
    match formatted {
        Ok(Some(title)) => title,
        Ok(None) => pos.pane.get_title(),
        Err(err) => {
            log::warn!("format-pane-title: {err}");
            pos.pane.get_title()
        }
    }
}

fn pane_title_line(text: &str, width: usize, attrs: CellAttributes) -> Line {
    let mut line = parse_status_text(text, attrs.clone());
    let original_len = line.len();
    line.resize(width, SEQ_ZERO);
    if original_len < width {
        for cell in &mut line.cells_mut()[original_len..] {
            *cell = Cell::blank_with_attrs(attrs.clone());
        }
    }
    line
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pane_title_callback_accepts_text_and_format_items() {
        let lua = mlua::Lua::new();
        assert_eq!(title_from_lua(mlua::Value::Nil, &lua).unwrap(), None);
        let text = lua.create_string("pane").unwrap();
        assert_eq!(
            title_from_lua(mlua::Value::String(text), &lua).unwrap(),
            Some("pane".to_string())
        );
        let items = lua.load("{{ Text = 'branch' }}").eval().unwrap();
        assert_eq!(
            title_from_lua(items, &lua).unwrap(),
            Some("branch".to_string())
        );
    }

    #[test]
    fn pane_title_is_clipped_to_its_own_width() {
        let attrs = CellAttributes::default();
        assert_eq!(pane_title_line("long title", 4, attrs.clone()).len(), 4);
        assert_eq!(pane_title_line("x", 4, attrs).len(), 4);
    }

    #[test]
    fn pane_title_cache_invalidates_on_focus_width_title_or_expiry() {
        let now = Instant::now();
        let entry = PaneTitleCacheEntry {
            text: "formatted".to_string(),
            expires: now + Duration::from_secs(1),
            width: 10,
            is_active: true,
            terminal_title: "shell".to_string(),
        };
        assert!(entry.valid(now, 10, true, "shell"));
        assert!(!entry.valid(now, 9, true, "shell"));
        assert!(!entry.valid(now, 10, false, "shell"));
        assert!(!entry.valid(now, 10, true, "vim"));
        assert!(!entry.valid(now + Duration::from_secs(1), 10, true, "shell"));
    }
}

impl crate::TermWindow {
    pub fn paint_pane_title(
        &mut self,
        pos: &PositionedPane,
        layers: &mut TripleLayerQuadAllocator,
    ) -> anyhow::Result<()> {
        let title_top = match pos.title_top {
            Some(top) => top,
            None => return Ok(()),
        };
        let cell_width = self.render_metrics.cell_size.width as usize;
        let cell_height = self.render_metrics.cell_size.height as usize;
        let (padding_left, padding_top) = self.padding_left_top();
        let border = self.get_os_border();
        let tab_height = if self.show_tab_bar && !self.config.tab_bar_at_bottom {
            self.tab_bar_pixel_height()?
        } else {
            0.
        };
        let left = padding_left + border.left.get() as f32 + (pos.left * cell_width) as f32;
        let top =
            tab_height + padding_top + border.top.get() as f32 + (title_top * cell_height) as f32;

        let colors = self
            .config
            .resolved_palette
            .tab_bar
            .clone()
            .unwrap_or_else(TabBarColors::default);
        let attrs = if pos.is_active {
            colors.active_tab().as_cell_attributes()
        } else {
            colors.inactive_tab().as_cell_attributes()
        };
        let now = Instant::now();
        let pane_id = pos.pane.pane_id();
        let terminal_title = pos.pane.get_title();
        let (title, expires) = match self.pane_title_cache.get(&pane_id) {
            Some(entry) if entry.valid(now, pos.width, pos.is_active, &terminal_title) => {
                (entry.text.clone(), entry.expires)
            }
            _ => {
                let text = format_pane_title(pos, &self.config);
                let expires = now + Duration::from_secs(1);
                self.pane_title_cache.insert(
                    pane_id,
                    PaneTitleCacheEntry {
                        text: text.clone(),
                        expires,
                        width: pos.width,
                        is_active: pos.is_active,
                        terminal_title,
                    },
                );
                (text, expires)
            }
        };
        self.update_next_frame_time(Some(expires));
        let line = pane_title_line(&title, pos.width, attrs);

        self.ui_items.push(UIItem {
            x: left as usize,
            y: top as usize,
            width: (pos.width * cell_width).saturating_sub(1),
            height: cell_height.saturating_sub(1),
            item_type: UIItemType::PaneTitle(pos.index),
        });

        let palette = self.palette().clone();
        let gl_state = self.render_state.as_ref().unwrap();
        self.render_screen_line(
            RenderScreenLineParams {
                top_pixel_y: top,
                left_pixel_x: left,
                pixel_width: (pos.width * cell_width) as f32,
                stable_line_idx: None,
                line: &line,
                selection: 0..0,
                cursor: &Default::default(),
                palette: &palette,
                dims: &RenderableDimensions {
                    cols: pos.width,
                    physical_top: 0,
                    scrollback_rows: 0,
                    scrollback_top: 0,
                    viewport_rows: 1,
                    dpi: self.terminal_size.dpi,
                    pixel_height: cell_height,
                    pixel_width: pos.width * cell_width,
                    reverse_video: false,
                },
                config: &self.config,
                pane: None,
                white_space: gl_state.util_sprites.white_space.texture_coords(),
                filled_box: gl_state.util_sprites.filled_box.texture_coords(),
                cursor_border_color: LinearRgba::default(),
                foreground: palette.foreground.to_linear(),
                is_active: pos.is_active,
                selection_fg: LinearRgba::default(),
                selection_bg: LinearRgba::default(),
                cursor_fg: LinearRgba::default(),
                cursor_bg: LinearRgba::default(),
                cursor_is_default_color: true,
                window_is_transparent: false,
                default_bg: palette.resolve_bg(ColorAttribute::Default).to_linear(),
                font: None,
                style: None,
                use_pixel_positioning: self.config.experimental_pixel_positioning,
                render_metrics: self.render_metrics,
                shape_key: None,
                password_input: false,
            },
            layers,
        )?;
        Ok(())
    }
}
