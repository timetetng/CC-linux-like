-- 井字棋游戏

-- 定义棋盘
local board = {}
for i = 1,3 do
  board[i]={}
  for j = 1,3 do
    board[i][j]=0
  end
end

board.__index=board

function board:set(x,y,v)
  self.x.y = v
  return self
end

function board:__tostring()
  local show = {}
  for i = 1,3 do
    show[i] = {}
    for j = 1,3 do
      if self[i][j]==1 then
        show[i][j]=="X"
      elseif self[i][j]==-1 then
        show[i][j]=="O"
      else
        show[i][j]==" "
      end
    end
  end

  return string.format("|%s|%s|%s|\n|%s|%s|%s|\n|%s|%s|%s|",table.unpack(show[1],table.unpack(show[2]),table.unpack[show[3]])
end
board:set(1,1,1)
board:set(1,2,-1)
print(board)
