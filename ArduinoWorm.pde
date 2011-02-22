
#include <avr/pgmspace.h>
#include <TVout.h>
#include <video_gen.h>
#include <EEPROM.h>
#include <Controllers.h>
#define TV_W 136
#define TV_H 98
#define FRAME_X0 8
#define FRAME_X1 128
#define FRAME_Y0 9
#define FRAME_Y1 89
#define LEFT 3
#define RIGHT 2
#define UP 4
#define DOWN 5
#define FIRE 10

struct Segment
{
  boolean active;
  byte x;
  byte y;
};


prog_char s0[] PROGMEM = "ARDUINO WORM";
prog_char s1[] PROGMEM = "GAME";
prog_char s2[] PROGMEM = "OVER";
prog_char s3[] PROGMEM = "SCORE: ";

PROGMEM const char *strings[] = {
  s0,s1,s2,s3};
char s[16]; // general string buffer
boolean useNunchuk = false;
byte currentTonePriority = 0;
byte ballX;
byte ballY;
byte movingDirection;
boolean ballCollected = false;
int currentScore;

Segment worm[50];

void (*game)();
TVout tv;

// Allow the overall speed of the game to be adjusted.
// Higher number (like 1.5) slow the game down.  Lower numbers (like 0.6) speed it up.
float speedAdjust = 1.0;

void setup()  {
  // If pin 12 is pulled LOW, then the PAL jumper is shorted.
  pinMode(12, INPUT);
  digitalWrite(12, HIGH);

  if (digitalRead(12) == LOW) {
    tv.begin(_PAL, TV_W, TV_H);
    // Since PAL processing is faster, we need to slow the game play down.
    speedAdjust = 1.4;
  } 
  else {
    tv.begin(_NTSC, TV_W, TV_H);
  }

  randomSeed(analogRead(0));

  playTone(1046, 20);
  tv.delay(1);
  playTone(1318, 20);
  tv.delay(1);
  playTone(1568, 20);
  tv.delay(1);
  playTone(2093, 20);

  // Detect whether nunchuk is connected.  Poll the nunchuk every 4th frame.
  useNunchuk = Nunchuk.init(tv, 4);
  if (useNunchuk) {
    // Speed up game play a bit because of the extra time it takes to
    // communicate with the nunchuk.
    speedAdjust *= 0.8;
  }

  byte m[1] = {
    0            };
  byte choice = menu(1, m);
  if (choice == 0) {
    game = &test;
    tv.delay(10);
    initTest();
  }
}

byte menu(byte nChoices, byte *choices) {
  char choice = 0;
  tv.fill(0);
  byte x = 24;
  byte y;

  while (true) {
    for(byte i=0;i<nChoices;i++) {
      strcpy_P(s, (char *)pgm_read_word(&(strings[choices[i]])));
      tv.print_str(32, 30+(i*8), s);
    }
    for(byte i=0;i<nChoices;i++) {
      y = 30+(i*8);
      if (i == choice) {
        // draw arrow next to selected game
        tv.set_pixel(x+4, y, 1);
        tv.set_pixel(x+5, y+1, 1);
        tv.draw_line(x, y+2, x+6, y+2, 1);
        tv.set_pixel(x+5, y+3, 1);
        tv.set_pixel(x+4, y+4, 1);
      } 
      else {
        for(byte j=0;j<8;j++) {
          tv.draw_line(x, y+j, x+7, y+j, 0);
        }
      }
    }
    // get input
    if (pollFireButton(10)) {
      playTone(1046, 20);
      return choice;	
    }
    // note that the call to pollFireButton above got data from the nunchuk device
    if ((Controller.upPressed()) || (useNunchuk && (Nunchuk.getJoystickY() > 200))) {
      choice--;
      if (choice == -1) {
        choice = 0;
      } 
      else {
        playTone(1046, 20);
      }
    }
    if ((Controller.downPressed()) || (useNunchuk && (Nunchuk.getJoystickY() < 100))) {
      choice++;
      if (choice == nChoices) {
        choice = nChoices-1;
      } 
      else {
        playTone(1046, 20);
      }
    }
  }
}

void initTest() {
  for(int x = 0; x < 5; x++) {
    worm[x].active = true;
    worm[x].x = 30-x;
    worm[x].y = 30;
  }
  for(int x = 5; x < 50; x++) {
    worm[x].active = false;
    worm[x].x = 0;
    worm[x].y = 0;
  }
  movingDirection = RIGHT;
  ballCollected = true;
  currentScore = 0;
}

void loop() {
  game();
}

void test() {
  tv.fill(0);
  drawFrame();
  drawScore();
  drawBall();
  for(int x = 0; x < 50; x++) {
    if(worm[x].active)
      tv.set_pixel(worm[x].x,worm[x].y,1);
  }
  move();
  tv.delay(1);
}

void drawBall() {
  if(ballCollected) {
    ballX = random(FRAME_X0+1, FRAME_X1-1);
    ballY = random(FRAME_Y0+1, FRAME_Y1-1);
    ballCollected = false;
  }
  tv.set_pixel(ballX,ballY,1);
}

void drawFrame() {
  tv.draw_line(FRAME_X0, FRAME_Y0, FRAME_X1, FRAME_Y0, 1);
  tv.draw_line(FRAME_X0, FRAME_Y1, FRAME_X1, FRAME_Y1, 1);
  tv.draw_line(FRAME_X0, FRAME_Y0, FRAME_X0, FRAME_Y1, 1);
  tv.draw_line(FRAME_X1, FRAME_Y0, FRAME_X1, FRAME_Y1, 1);
}

void move() {
  if (Controller.upPressed()) {
    if(movingDirection != DOWN) {
      movingDirection = UP;
    }
  } 
  else if(Controller.downPressed()) {
    if(movingDirection != UP) {
    movingDirection = DOWN;
    }
  } 
  else if(Controller.leftPressed()) {
    if(movingDirection != RIGHT) {
    movingDirection = LEFT;
    }
  } 
  else if(Controller.rightPressed()) {
    if(movingDirection != LEFT) {
    movingDirection = RIGHT;
    }
  }
  switch (movingDirection) {
  case UP:
    if(detectBallHit(worm[0].x, worm[0].y-1)) {
      assignBallCoordinatesToFirstSegment();
    } 
    else { 
      shiftSegments();
      worm[0].y = worm[0].y-1   ;
    }
    break;
  case DOWN:
    if(detectBallHit(worm[0].x, worm[0].y+1)){
      assignBallCoordinatesToFirstSegment();
    } 
    else {
      shiftSegments(); 
      worm[0].y = worm[0].y+1   ;
    }
    break;
  case LEFT: 
    if(detectBallHit(worm[0].x-1, worm[0].y)){
      assignBallCoordinatesToFirstSegment();
    }
    else {
      shiftSegments(); 
      worm[0].x = worm[0].x-1   ;
    }
    break;
  case RIGHT: 
    if(detectBallHit(worm[0].x+1, worm[0].y)){
      assignBallCoordinatesToFirstSegment();
    }
    else {
      shiftSegments(); 
      worm[0].x = worm[0].x+1   ;
    }
    break;
  }
   if(worm[0].x > FRAME_X1-1 || worm[0].x < FRAME_X0+1 || worm[0].y > FRAME_Y1-1 || worm[0].y < FRAME_Y0+1 || checkForTailBite()) {
    gameOver();
    initTest();
    return;
  } 
}

boolean checkForTailBite() {
  for(int x = 1; x < 50; x++) {
    if(worm[0].x == worm[x].x && worm[0].y == worm[x].y) {
      return true;
    }
  }
  return false;
}

void shiftSegments() {
  for(int x = 49; x > 0; x--) {
    if(worm[x].active) {
      worm[x].x = worm[x-1].x;
      worm[x].y = worm[x-1].y;
    }
  }
}

void assignBallCoordinatesToFirstSegment() {
  worm[0].x = ballX;
  worm[0].y = ballY;
}

boolean detectBallHit(byte sx, byte sy) {
  if(sx == ballX && sy == ballY) {
    for(int x = 49; x > -1; x--) {
      if(worm[x].active) {
        worm[x+1].active = true;
        worm[x+1].x = worm[x].x;
        worm[x+1].y = worm[x].y;  
      }
    }
    ballCollected = true;
    currentScore += 1;
    playTone(1046, 10);
    tv.delay(1);
    playTone(1318, 10);
    tv.delay(1);
    playTone(1568, 10);
    tv.delay(1);
    playTone(2093, 10);
    return true;
  } 
  else {
    return false;
  }
}

void drawScore() {
  tv.select_font(_5X7);
  strcpy_P(s, (char *)pgm_read_word(&(strings[3])));
  tv.print_str(FRAME_X0, 0, s);
  String currentScoreStr = String(currentScore);
  // for whatever reason, the print_str method doesn't print strings whith only one character
  if(currentScoreStr.length() < 2) {
    currentScoreStr += " ";
  }
  char scoreChars[currentScoreStr.length()];
  currentScoreStr.toCharArray(scoreChars, currentScoreStr.length());
  tv.print_str(70, 0, scoreChars);
}

void gameOver() {
  tv.delay(60);
  tv.fill(0);
  tv.select_font(_5X7);
  strcpy_P(s, (char *)pgm_read_word(&(strings[1])));
  tv.print_str(44, 40, s);
  strcpy_P(s, (char *)pgm_read_word(&(strings[2])));
  tv.print_str(72, 40, s);
  tv.delay(180);
}

boolean pollFireButton(int n) {
  for(int i=0;i<n;i++) {
    if (useNunchuk) {
      Nunchuk.getData();
    }
    tv.delay(1);
    if ((Controller.firePressed()) || (useNunchuk && (Nunchuk.getButtonZ() == 1))) {
      return true;
    }
  }
  return false;
}

void playTone(unsigned int frequency, unsigned long duration_ms) {
  // Default is to play tone with highest priority.
  playTone(frequency, duration_ms, 9);
}

void playTone(unsigned int frequency, unsigned long duration_ms, byte priority) {
  // priority is value 0-9, 9 being highest priority
  if (TCCR2B > 0) {
    // If a tone is currently playing, check priority
    if (priority < currentTonePriority) {
      return;
    }
  }
  currentTonePriority = priority;
  tv.tone(frequency, duration_ms);
}

