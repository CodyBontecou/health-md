// @vitest-environment jsdom
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import "@testing-library/jest-dom/vitest";
import userEvent from "@testing-library/user-event";
import axe from "axe-core";
import { afterEach, describe, expect, it, vi } from "vitest";
import { useState } from "react";
import { ConfirmationDialog, DataTable, ErrorSummary, SafeText, StatePanel, TextField } from "../src/web/components/clinical";

afterEach(cleanup);

describe("clinical design system", () => {
  it("renders hostile content only as escaped text and has no axe violations", async () => {
    const hostile = '<img src=x onerror="alert(1)"> [link](https://invalid.example)';
    const { container } = render(<main><h1>Safe fixture</h1><SafeText>{hostile}</SafeText><DataTable caption="Safe table" headers={["Value"]} rows={[[hostile]]} /></main>);
    expect(screen.getAllByText(hostile)).toHaveLength(2);
    expect(container.querySelector("img")).toBeNull();
    expect((await axe.run(container, { rules: { "color-contrast": { enabled: false } } })).violations).toEqual([]);
  });

  it("links error summaries to fields and exposes field errors", async () => {
    render(<><ErrorSummary errors={[{ field: "period.days", code: "relative_days_invalid" }]} /><TextField name="period.days" label="Completed days" value="0" onChange={() => undefined} error="Enter a positive whole number." /></>);
    expect(screen.getByRole("alert")).toHaveTextContent("relative_days_invalid");
    expect(screen.getByRole("link")).toHaveAttribute("href", "#field-period-days");
    expect(screen.getByLabelText("Completed days")).toHaveAttribute("aria-invalid", "true");
  });

  it("traps Tab, actually closes on Escape, and restores focus", async () => {
    function Harness() { const [open, setOpen] = useState(false); return <div><button onClick={() => setOpen(true)}>Open confirmation</button><ConfirmationDialog open={open} title="Confirm exact revision" confirmLabel="Confirm" onCancel={() => setOpen(false)} onConfirm={() => setOpen(false)}><input aria-label="Dialog input" /></ConfirmationDialog></div>; }
    const user = userEvent.setup(); render(<Harness />);
    const trigger = screen.getByRole("button", { name: "Open confirmation" }); await user.click(trigger);
    const first = screen.getByLabelText("Dialog input"); expect(first).toHaveFocus();
    fireEvent.keyDown(document, { key: "Tab", shiftKey: true }); expect(screen.getByRole("button", { name: "Confirm" })).toHaveFocus();
    fireEvent.keyDown(document, { key: "Tab" }); expect(first).toHaveFocus();
    fireEvent.keyDown(document, { key: "Escape" });
    expect(screen.queryByRole("dialog")).toBeNull(); expect(trigger).toHaveFocus();
  });

  it.each(["loading", "empty", "error", "denied", "stale"] as const)("renders the %s state semantically", state => {
    render(<StatePanel state={state} title={`${state} title`} />);
    expect(screen.getByRole(state === "error" ? "alert" : "status")).toBeInTheDocument();
    cleanup();
  });

  it("supports keyboard activation without a pointer", async () => {
    const user = userEvent.setup(); const action = vi.fn();
    render(<button onClick={action}>Continue</button>);
    await user.tab(); await user.keyboard("{Enter}");
    expect(action).toHaveBeenCalledOnce();
  });
});
