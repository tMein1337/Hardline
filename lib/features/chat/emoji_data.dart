// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

// The emoji the reaction picker offers.
//
// A curated set rather than the whole Unicode list: a reaction is chosen in a
// second or two, and several thousand near-identical faces and flags would
// make the grid slower to use, not better. Anything missing here can still be
// typed into the picker's search box and sent as it is.

/// The six offered first, one click away.
const quickReactions = ['👍', '❤️', '😂', '😮', '😢', '🎉'];

/// One emoji and the words it is found by.
typedef EmojiEntry = ({String emoji, String keywords});

/// A heading in the picker and what is under it.
typedef EmojiCategory = ({String name, List<EmojiEntry> emoji});

List<EmojiEntry> _parse(String table) => [
  for (final line in table.trim().split('\n'))
    if (line.trim().isNotEmpty)
      (
        emoji: line.trim().split(' ').first,
        keywords: line.trim().split(' ').skip(1).join(' '),
      ),
];

final emojiCategories = <EmojiCategory>[
  (
    name: 'Smileys',
    emoji: _parse('''
😀 grinning smile happy
😃 smiley happy joy
😄 smile happy laugh
😁 grin beaming
😆 laughing satisfied
😅 sweat smile relief
🤣 rofl rolling laughing
😂 joy tears laughing lol
🙂 slightly smiling
🙃 upside down
😉 wink
😊 blush smiling
😇 innocent halo angel
🥰 love hearts adore
😍 heart eyes love
🤩 star struck wow
😘 kiss blow
😋 yum delicious
😛 tongue
😜 wink tongue crazy
🤪 zany goofy
😝 squint tongue
🤑 money
🤗 hug hugging
🤭 hand over mouth oops
🤫 shush quiet secret
🤔 thinking hmm
🤐 zipper mouth
🤨 raised eyebrow skeptical
😐 neutral
😑 expressionless
😶 no mouth speechless
😏 smirk
😒 unamused
🙄 eye roll
😬 grimace awkward
😌 relieved
😔 pensive
😪 sleepy
😴 sleeping zzz
😷 mask sick
🤒 thermometer ill
🤢 nauseated sick
🤮 vomit
🥵 hot
🥶 cold freezing
🥴 woozy dizzy
😵 dizzy knocked out
🤯 mind blown exploding
🤠 cowboy
🥳 party celebrate
😎 cool sunglasses
🤓 nerd
🧐 monocle
😕 confused
😟 worried
🙁 frown
😮 open mouth wow surprised
😯 hushed
😲 astonished shocked
😳 flushed embarrassed
🥺 pleading puppy eyes
😦 frowning open mouth
😧 anguished
😨 fearful scared
😰 anxious sweat
😥 sad relieved
😢 cry sad tear
😭 sob crying loudly
😱 scream fear
😖 confounded
😣 persevere
😞 disappointed
😓 downcast sweat
😩 weary
😫 tired
🥱 yawn bored
😤 triumph huff
😡 pouting angry rage
😠 angry mad
🤬 cursing swearing
😈 smiling devil
👿 imp angry devil
💀 skull dead
💩 poop
🤡 clown
👻 ghost
👽 alien
🤖 robot
'''),
  ),
  (
    name: 'People',
    emoji: _parse('''
👍 thumbs up yes like +1
👎 thumbs down no dislike -1
👌 ok okay perfect
🤌 pinched fingers
✌️ victory peace
🤞 crossed fingers luck
🤟 love you gesture
🤘 rock horns
🤙 call me shaka
👈 point left
👉 point right
👆 point up
👇 point down
☝️ index up
👋 wave hello bye
🤚 raised back of hand
✋ raised hand stop high five
🖖 vulcan
👏 clap applause
🙌 raised hands hooray
👐 open hands
🤲 palms up
🤝 handshake deal
🙏 pray please thanks
✍️ writing
💪 muscle strong flex
🫡 salute
🫶 heart hands
👀 eyes looking
👁️ eye
🧠 brain smart
🫠 melting
🤷 shrug dunno
🤦 facepalm
🙇 bow
🙋 raising hand
🙆 ok gesture
🙅 no gesture
💁 tipping hand
🧑‍💻 technologist coder
🧙 mage wizard
🥷 ninja
'''),
  ),
  (
    name: 'Hearts',
    emoji: _parse('''
❤️ red heart love
🧡 orange heart
💛 yellow heart
💚 green heart
💙 blue heart
💜 purple heart
🖤 black heart
🤍 white heart
🤎 brown heart
💔 broken heart
❤️‍🔥 heart on fire
💕 two hearts
💞 revolving hearts
💓 beating heart
💗 growing heart
💖 sparkling heart
💘 heart arrow cupid
💝 heart ribbon gift
💯 hundred 100 perfect
💢 anger
💥 boom collision
💫 dizzy star
💦 sweat drops
💨 dash
💬 speech bubble
💭 thought bubble
💤 zzz sleep
'''),
  ),
  (
    name: 'Nature',
    emoji: _parse('''
🐶 dog puppy
🐱 cat kitten
🐭 mouse
🐹 hamster
🐰 rabbit bunny
🦊 fox
🐻 bear
🐼 panda
🐨 koala
🐯 tiger
🦁 lion
🐮 cow
🐷 pig
🐸 frog
🐵 monkey
🙈 see no evil
🙉 hear no evil
🙊 speak no evil
🐔 chicken
🐧 penguin
🐦 bird
🦆 duck
🦉 owl
🦄 unicorn
🐝 bee
🐛 bug
🦋 butterfly
🐢 turtle
🐍 snake
🐙 octopus
🦀 crab
🐬 dolphin
🐳 whale
🦈 shark
🌵 cactus
🌲 tree evergreen
🍀 clover luck
🍁 maple leaf
🌸 cherry blossom
🌹 rose
🌻 sunflower
🌞 sun face
🌙 moon
⭐ star
🌟 glowing star
✨ sparkles
⚡ zap lightning
🔥 fire hot lit
🌈 rainbow
☀️ sun sunny
☁️ cloud
❄️ snowflake cold
🌊 wave ocean
'''),
  ),
  (
    name: 'Food',
    emoji: _parse('''
🍎 apple
🍌 banana
🍉 watermelon
🍇 grapes
🍓 strawberry
🍒 cherries
🍑 peach
🥑 avocado
🌶️ hot pepper chili
🥕 carrot
🌽 corn
🥐 croissant
🥨 pretzel
🧀 cheese
🍔 burger hamburger
🍟 fries
🍕 pizza
🌭 hot dog
🌮 taco
🍣 sushi
🍜 ramen noodles
🍿 popcorn
🍩 doughnut donut
🍪 cookie
🎂 birthday cake
🍰 cake shortcake
🍫 chocolate
🍬 candy
☕ coffee
🍵 tea
🍺 beer
🍻 cheers beers
🍷 wine
🥂 champagne toast
🧃 juice box
'''),
  ),
  (
    name: 'Activities',
    emoji: _parse('''
🎉 tada party celebrate
🎊 confetti
🎈 balloon
🎁 gift present
🏆 trophy winner
🥇 gold medal first
🥈 silver medal second
🥉 bronze medal third
⚽ soccer football
🏀 basketball
🏈 american football
🎾 tennis
🎮 video game controller gaming
🕹️ joystick
🎲 dice game
🎯 bullseye target direct hit
🎳 bowling
🧩 puzzle
♟️ chess
🎸 guitar
🎹 piano
🥁 drum
🎤 microphone sing
🎧 headphones
🎬 clapper movie
🎨 art palette
🚀 rocket launch ship
✈️ airplane
🚗 car
🏁 checkered flag finish
'''),
  ),
  (
    name: 'Objects',
    emoji: _parse('''
💻 laptop computer
🖥️ desktop computer
⌨️ keyboard
🖱️ mouse computer
📱 phone mobile
🔋 battery
🔌 plug
💡 bulb idea
🔦 flashlight
📷 camera
📺 television tv
⏰ alarm clock
⌛ hourglass
📌 pushpin
📎 paperclip
✏️ pencil
📝 memo note
📚 books
📦 package box
📫 mailbox
🔒 lock locked
🔓 unlocked
🔑 key
🔨 hammer
🛠️ tools
⚙️ gear settings
🧪 test tube
🔭 telescope
💊 pill
🛡️ shield
💰 money bag
💎 gem diamond
🔔 bell
📣 megaphone
🗑️ wastebasket trash
'''),
  ),
  (
    name: 'Symbols',
    emoji: _parse('''
✅ check done yes
☑️ ballot check
✔️ check mark
❌ cross no wrong
❎ cross mark button
➕ plus
➖ minus
❓ question
❗ exclamation
‼️ double exclamation
⚠️ warning
🚫 prohibited
⛔ no entry
🔴 red circle
🟠 orange circle
🟡 yellow circle
🟢 green circle
🔵 blue circle
🟣 purple circle
⚫ black circle
⚪ white circle
🆗 ok button
🆕 new
🆒 cool button
🔝 top
🔜 soon
♻️ recycle
⬆️ up arrow
⬇️ down arrow
⬅️ left arrow
➡️ right arrow
🔁 repeat
➰ loop
'''),
  ),
];

/// Emoji whose keywords contain every word of [query], in picker order.
List<String> searchEmoji(String query) {
  final words = query.toLowerCase().split(RegExp(r'\s+'))
    ..removeWhere((word) => word.isEmpty);
  if (words.isEmpty) return const [];
  return [
    for (final category in emojiCategories)
      for (final entry in category.emoji)
        if (words.every(entry.keywords.contains)) entry.emoji,
  ];
}
