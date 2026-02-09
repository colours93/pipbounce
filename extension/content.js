(() => {
  // Only run in frames that have a video
  const video = Array.from(document.querySelectorAll("video"))
    .filter((v) => v.readyState > 0 && !v.disablePictureInPicture)
    .sort(
      (a, b) =>
        b.clientWidth * b.clientHeight - a.clientWidth * a.clientHeight
    )[0];

  if (!video) return;

  // If this video is already in PiP, exit
  if (document.pictureInPictureElement === video) {
    document.exitPictureInPicture();
    return;
  }

  // If no PiP is active anywhere, enter PiP
  if (!document.pictureInPictureElement) {
    video.requestPictureInPicture().catch(() => {});
  }
})();
