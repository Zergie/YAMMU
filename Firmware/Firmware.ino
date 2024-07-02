// options
#define CH340E 1
#define DEBUG 1
#define PWM_CYCLE_TIME 0.1 // in seconds, just like in your klipper config
#define LOOP_FREQ 250
#define BE_DEBOUNCE 200

// used pins
#define BE1 PB13
#define BE2 PB14
#define PWM_DELAY PB3
#define PWM_SPEED PB4
#define PWM_SEL PB5
#define PWM_SPEEDM PB6
#define LED PC13
uint32_t motor_pins[] = {PB11, PB10};
// todo: add M2..19

// pwm decoding
uint32_t pwm_state[][4] = {
  {0, 0, 0, PWM_DELAY},
  {0, 0, 0, PWM_SPEED},
  {0, 0, 0, PWM_SEL},
  {0, 0, 0, PWM_SPEEDM},
};
void ISR_0() { ISR(0); }
void ISR_1() { ISR(1); }
void ISR_2() { ISR(2); }
void ISR_3() { ISR(3); }
void ISR(uint32_t index) {
  uint32_t time = micros();
  switch (digitalRead(pwm_state[index][3])) {
    case HIGH: // start on high
      pwm_state[index][0] = time;
      break;
    case LOW: // stop on LOW
      pwm_state[index][1] = time;
      pwm_state[index][2] = pwm_state[index][1] - pwm_state[index][0]; 
      break;
  }  
}
uint32_t time_be1 = 0;
void ISR_BE1() {
  uint32_t time = millis();
  if (digitalRead(BE1) && time - time_be1 > BE_DEBOUNCE) {
    time_be1 = time;
  }
}


uint32_t motor_pin = 99;
void setup() {
  // inputs
  pinMode(BE1, INPUT_PULLUP);
  pinMode(BE2, INPUT_PULLUP);
  pinMode(PWM_DELAY, INPUT_PULLUP);
  pinMode(PWM_SPEED, INPUT_PULLUP);
  pinMode(PWM_SEL, INPUT_PULLUP);
  pinMode(PWM_SPEEDM, INPUT_PULLUP);

  // outputs
  pinMode(LED, OUTPUT);
  digitalWrite(LED, HIGH);
  for (int i = 0; i < sizeof(motor_pins); i++) {
    pinMode(motor_pins[i], OUTPUT);
    digitalWrite(motor_pins[0], LOW);
  }

  // setting up interrupts
  attachInterrupt(digitalPinToInterrupt(pwm_state[0][3]), ISR_0, CHANGE);
  attachInterrupt(digitalPinToInterrupt(pwm_state[1][3]), ISR_1, CHANGE);
  attachInterrupt(digitalPinToInterrupt(pwm_state[2][3]), ISR_2, CHANGE);
  attachInterrupt(digitalPinToInterrupt(pwm_state[3][3]), ISR_3, CHANGE);
  attachInterrupt(digitalPinToInterrupt(BE1), ISR_BE1, FALLING);

  #if DEBUG
    // init serial
    #if CH340E
      Serial.setTx(PA9);
      Serial.setRx(PA10);
    #endif
    Serial.begin(9600);
    while(!Serial);
  #endif

  delay(1000);
}

void loop() {
  uint32_t time = micros();

  uint32_t pwm_value[4] = {0};
  for (int i = 0; i < 4; i++) {
    uint32_t value = (time - pwm_state[i][0]) > (2 * PWM_CYCLE_TIME * 1000000) ?
                     digitalRead(pwm_state[i][3]) * 100 :
                     pwm_state[i][2] / (PWM_CYCLE_TIME * 10000);
    
    if (0 <= value && value <= 100) {
      pwm_value[i] = value;
    }
  }

  uint32_t motor_delay = 4000 * pwm_value[0] / 100;
  uint32_t motor_speed = 255 * pwm_value[1] / 100;
  uint32_t motor_manual = 255 - (255 * pwm_value[3] / 100);
  
  uint32_t old_motor_pin = motor_pin;
  motor_pin = pwm_value[2] / 5;
  if (old_motor_pin != 99 && old_motor_pin != motor_pin) {
    analogWrite(motor_pins[old_motor_pin], 0);
  }
  
  if (motor_manual > 0) {
    digitalWrite(LED, HIGH);
    analogWrite(motor_pins[motor_pin], motor_manual);
  } else if (time_be1 > 0) {
    digitalWrite(LED, HIGH);
    analogWrite(motor_pins[motor_pin], motor_speed);

    if (millis() - time_be1 - motor_delay < LOOP_FREQ) {
      uint32_t wait = millis() - time_be1 - motor_delay;
      delay(wait); 
    } 
    
    if (millis() - time_be1 >= motor_delay) {
      analogWrite(motor_pins[motor_pin], 0);
      digitalWrite(LED, LOW);
      time_be1 = 0;
    }
  } else {
    digitalWrite(LED, LOW);
    analogWrite(motor_pins[motor_pin], LOW);
  }

  // if (digitalRead(BE2) == LOW) {
  // }

  #if DEBUG
    Serial.print(digitalRead(BE1));
    Serial.print(",");
    Serial.print(time_be1);
    Serial.print(",");
    Serial.print(motor_delay);
    Serial.print(",");
    Serial.print(motor_speed);
    Serial.print(",");
    Serial.print(motor_pin);
    Serial.print(",");
    Serial.print(motor_manual);
    Serial.print(",");
    Serial.println();
  #endif
  delay(LOOP_FREQ);
}
