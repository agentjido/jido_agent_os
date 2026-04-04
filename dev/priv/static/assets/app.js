(() => {
  if (!window.Phoenix || !window.LiveView) return

  const csrfToken =
    document.querySelector("meta[name='csrf-token']")?.getAttribute("content")

  const liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
    params: {_csrf_token: csrfToken},
    longPollFallbackMs: 2_500
  })

  liveSocket.connect()
  window.liveSocket = liveSocket
})()
