library ieee;
use ieee.std_logic_1164.all;
use IEEE.NUMERIC_STD.all;

library work;
use work.cam_pkg.all;

entity line_buffer is
  generic (
    ID        : integer range 0 to 63   := 0;
    NUM_LINES : natural := 3;
    WIDTH     : natural range 1 to 2048 := 2048;
    HEIGHT    : natural range 1 to 2048 := 2048);
  port (
    pipe_in     : in  pipe_t;
    pipe_out    : out pipe_t;
    stall_in    : in  std_logic;
    stall_out   : out std_logic;
    mono_1d_out : out mono_1d_t
    );
end line_buffer;

architecture impl of line_buffer is

  signal clk        : std_logic;
  signal rst        : std_logic;
  signal stage      : stage_t;
  signal stage_next : stage_t;
  signal src_valid  : std_logic;
  signal issue      : std_logic;
  signal stall      : std_logic;

  type reg_t is record
    cols : natural range 0 to WIDTH;
    rows : natural range 0 to HEIGHT;
    sel  : natural range 0 to (NUM_LINES-1);
  end record;

  signal stalled : std_logic := '0';
  signal r      : reg_t;
  signal r_next : reg_t;

  procedure init (variable v : inout reg_t) is
  begin
    v.sel  := 0;
    v.cols := 0;
    v.rows := 0;
  end init;

  type   shift_t is array (0 to (NUM_LINES-1)) of mono_t;
  
  signal shiftin : shift_t;
  signal shiftout : shift_t;
    
begin
  issue <= '0';

  connect_pipe(clk, rst, pipe_in, pipe_out, stall_in, stall_out, stage, src_valid, issue, stall);

  rams : for i in 0 to (NUM_LINES-1) generate
    my_shiftreg: entity work.shiftreg
      generic map (
        WIDTH => 1,
        DEPTH => WIDTH)
      port map (
        clk      => clk,                -- [in]
        rst      => rst,                -- [in]
        shiftin  => shiftin(i),            -- [in]
        shiftout => shiftout(i),           -- [in]
        enable   => src_valid);            -- [in]
  end generate rams;

  
  process(pipe_in, stage, r, src_valid, rst, q, shiftin, shiftout)
    variable v : reg_t;
  begin  -- process
    stage_next <= pipe_in.stage;
    v          := r;
-------------------------------------------------------------------------------
-- Counters
-------------------------------------------------------------------------------
    if src_valid = '1' then
      if r.cols = (WIDTH-1) then
        v.cols := 0;

        if r.sel < (NUM_LINES-1) then
          v.sel := r.sel + 1;
        else
          v.sel := 0;
        end if;
        
        if (r.rows = (HEIGHT-1)) then
          v.rows := 0;
          v.sel  := 0;
        else
          v.rows := r.rows + 1;
        end if;
      else
        v.cols := v.cols + 1;
      end if;
    end if;
-------------------------------------------------------------------------------
-- Generate data from pipeline
-------------------------------------------------------------------------------

    shiftin(0) <= pipe_in.stage.data_1;
    shiftin(1) <= shiftout(0);
    shiftin(2) <= shiftout(1);
    shiftin(3) <= shiftout(2);    
    shiftin(4) <= shiftout(3);    

    
    mono_1d_out(0) <= stage.data_1;
    mono_1d_out(1) <= shiftout(0);
    mono_1d_out(2) <= shiftout(1);
    mono_1d_out(3) <= shiftout(2);
    mono_1d_out(4) <= shiftout(3);
    
-------------------------------------------------------------------------------
-- Reset
-------------------------------------------------------------------------------
    if pipe_in.cfg(ID).identify = '1' then
      stage_next.identity <= IDENT_LINEBUFFER;
    end if;
    if rst = '1' then
      init(v);
      stage_next <= NULL_STAGE;
    end if;
-------------------------------------------------------------------------------
-- Next
-------------------------------------------------------------------------------
    r_next <= v;
  end process;

  proc_clk : process(clk, rst, stall, stalled, src_valid, r_next, stage_next, pipe_in, qd, qi, q)
  begin
    if rising_edge(clk) and (stall = '0' or rst = '1') then
      if (pipe_in.cfg(ID).enable = '1') then
        stage <= stage_next;
      else
        stage <= pipe_in.stage;
      end if;
    end if;
  end process;

end impl;