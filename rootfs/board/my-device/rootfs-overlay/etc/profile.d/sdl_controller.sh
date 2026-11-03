# SDL's a: is the south button apps confirm with: A (right) by default, B (bottom) with confirm=b
# (System Settings > Input Settings > Confirm button)
A=b1 B=b0
grep -qx "confirm=b" /home/player/.config/puppy/settings 2>/dev/null && A=b0 B=b1
export SDL_GAMECONTROLLERCONFIG="1900c621474133362d4d422047616d00,GA36-MB Gamepad,dpleft:b15,rightx:a2,dpright:b16,rightshoulder:b5,dpdown:b14,righty:a3,leftshoulder:b4,y:b3,x:b2,b:$B,a:$A,dpup:b13,back:b8,leftstick:b11,start:b9,lefty:a1,guide:b8,lefttrigger:b6,righttrigger:b7,rightstick:b12,leftx:a0,platform:Linux"
unset A B
