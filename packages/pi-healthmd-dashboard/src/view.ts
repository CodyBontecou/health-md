import { initialView, type ViewState } from "./model.js";

export type ViewAction = "show" | "hide" | "select" | "focus" | "mode" | "date_window" | "zoom_in" | "zoom_out" | "pan_left" | "pan_right" | "reset";

export interface ViewUpdate {
  action: ViewAction;
  target?: string;
  targetKind?: "metric" | "path" | "search";
  mode?: "chart" | "table";
  startDate?: string;
  endDate?: string;
}

export function updateView(current: ViewState, update: ViewUpdate): ViewState {
  if (update.action === "reset") return { ...initialView(), visible: current.visible };
  const next = { ...current };
  if (update.action === "show") next.visible = true;
  if (update.action === "hide") next.visible = false;
  if (update.action === "select" || update.action === "focus") {
    if (!update.target) throw new Error(`${update.action} requires target`);
    next.target = update.target;
    next.targetKind = update.targetKind ?? "metric";
    next.offset = 0;
  }
  if (update.action === "mode") {
    if (!update.mode) throw new Error("mode action requires chart or table");
    next.mode = update.mode;
  }
  if (update.action === "date_window") {
    if (!update.startDate || !update.endDate) throw new Error("date_window requires startDate and endDate");
    if (update.startDate > update.endDate) throw new Error("startDate must not follow endDate");
    next.startDate = update.startDate;
    next.endDate = update.endDate;
  }
  if (update.action === "zoom_in") next.windowSize = Math.max(1, Math.floor(next.windowSize / 2));
  if (update.action === "zoom_out") next.windowSize = Math.min(3650, next.windowSize * 2);
  if (update.action === "pan_left") next.offset = Math.max(0, next.offset - Math.max(1, Math.floor(next.windowSize / 2)));
  if (update.action === "pan_right") next.offset = Math.max(0, next.offset + Math.max(1, Math.floor(next.windowSize / 2)));
  return next;
}
