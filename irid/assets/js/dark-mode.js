// Bridge the OS-level colour-scheme preference into irid's reactive
// graph.  Registered as a widget so it:
//   • participates in the irid lifecycle (mounts/tears down with session)
//   • rides the native wire channel for reliable client→server delivery
//   • cleans up the matchMedia listener on destroy
//
// The R side consumes this through IridWidget(name = "dark-mode-detector",
// events = list(`scheme-change` = handler)).

window.irid.defineWidget("dark-mode-detector", function (el, _props, sendEvent) {
  var mq = window.matchMedia("(prefers-color-scheme: dark)");

  function onChange(e) {
    sendEvent("scheme-change", { dark: e.matches });
  }

  // Defer the initial send until after the *entire* render pass
  // (widget-init + wire ops + irid-ready) has completed.
  // Calling sendEvent synchronously during factory construction
  // races the wire-op application — the channel isn't registered
  // yet and the event is silently dropped.
  // setTimeout(fn, 0) runs in a fresh event-loop task, after every
  // synchronous op in this render pass has been applied.
  setTimeout(function () {
    onChange(mq);
  }, 0);

  mq.addEventListener("change", onChange);

  return {
    destroy: function () {
      mq.removeEventListener("change", onChange);
    }
  };
});
