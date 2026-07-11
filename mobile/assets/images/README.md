# Image assets

- `chat_bot.png` — the robot mascot used by the support-chat launcher
  (draggable bubble) and as the chatbot's avatar in the live chat.
  512×512, transparent background, sized so the whole mascot fits the
  inscribed circle of the square (round avatars clip to a circle).
  Source render: `ai-robot.png` (1280×1280); regenerate by trimming the
  alpha bbox (threshold >24 to ignore the soft shadow) and padding to
  the mascot's bounding circle + 3%.
