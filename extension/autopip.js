// Auto-PiP: when you switch tabs while a video is playing, it pops into PiP automatically
navigator.mediaSession.setActionHandler("enterpictureinpicture", async () => {
  const video = Array.from(document.querySelectorAll("video"))
    .filter((v) => v.readyState > 0 && !v.disablePictureInPicture && !v.paused)
    .sort(
      (a, b) =>
        b.clientWidth * b.clientHeight - a.clientWidth * a.clientHeight
    )[0];

  if (video) {
    await video.requestPictureInPicture();
  }
});
