# Changelog

## 2.1 - 2026-10-11
- The bug keeps a fixed size: the PP badge has reserved space on each side, and the name, score, clock and period cells have fixed widths.

## 2.0 - 2026-10-11
- Rebuilt as a custom overlay for ScoreSight 0.3.0's browser overlays: values are pushed the moment they change, and ScoreSight serves the file.
- Misread protection is measured in time (0.6 s for a goal) where 1.0 counted polls.
- Scales with the page width; the clock box may be named `Time` or `Clock`.
- Accepts ScoreSight's ordinal period values ("1st", "4th").

## 1.0 - 2026-09-16
- First version: a standalone page polling ScoreSight 0.1.0's `/json`.
