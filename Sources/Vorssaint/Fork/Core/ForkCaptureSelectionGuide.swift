// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

/// Upstream's selection shows a hint bar over the screen ("drag to select an
/// area, click a window"). The capture menu has a bar of its own that already
/// says what can be done, so the selections it starts ask for no hint.
///
/// Set by the capture menu around its selection and read by one line of
/// upstream's selection view. Only one selection is on screen at a time, and
/// everything here happens on the main thread.
enum ForkCaptureSelectionGuide {
    static var isHidden = false
}
