library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity audio_ctrl is
  generic (
    ref_clk_freq_g : integer := 12288000;
    sample_rate_g  : integer := 48000;
    data_width_g   : integer := 16
  );
  port (
    clk           : in  std_logic;
    rst_n         : in  std_logic;
    left_data_in  : in  std_logic_vector(data_width_g-1 downto 0);
    right_data_in : in  std_logic_vector(data_width_g-1 downto 0);
    aud_bclk_out  : out std_logic;
    aud_data_out  : out std_logic;
    aud_lrclk_out : out std_logic
  );
end audio_ctrl;

architecture rtl of audio_ctrl is
	
	constant bclk_max_c  : integer := ref_clk_freq_g / (2*2*data_width_g*sample_rate_g);

	signal right_data_r  : std_logic_vector(data_width_g-1 downto 0);
	signal shift_r       : std_logic_vector(data_width_g-1 downto 0);
	signal data_out_r    : std_logic;
	signal bit_cnt_r     : integer range 0 to data_width_g-1;
	
	signal bclk_r        : std_logic;
	signal bclk_cnt_r    : integer range 0 to bclk_max_c-1;
	signal bclk_fall_r   : std_logic;
	
	signal lrclk_r       : std_logic;
	signal sync_r        : std_logic;

begin

	aud_data_out <= data_out_r;
	aud_bclk_out <= bclk_r;
	aud_lrclk_out <= lrclk_r;
	
  process (clk, rst_n)
    begin

      -- Initialization on reset

      if (rst_n = '0') then
        right_data_r  <= (others => '0');
        shift_r       <= (others => '0');
        data_out_r    <= '0';
        bit_cnt_r     <= 0;
        bclk_r        <= '0';
        bclk_cnt_r    <= 0;
        bclk_fall_r   <= '0';
        lrclk_r       <= '0';
        sync_r        <= '0';

      elsif (clk'event and clk = '1') then

        -- Reset bclk falling edge flag

        bclk_fall_r  <= '0';

        -- Generate bclk

        if (bclk_cnt_r = bclk_max_c-1) then
          bclk_cnt_r <= 0;
          if(bclk_r = '1') then
            bclk_fall_r <= '1';
          end if;
          bclk_r <= not bclk_r;
        else
          bclk_cnt_r <= bclk_cnt_r+1;
        end if;

        -- Sync bclk and lrclk
        -- Snapshot data inputs
        -- First data transition begins left channel first, then right

        if (sync_r = '0' and bclk_fall_r = '1') then
          lrclk_r <= '1';
          sync_r <= '1';
          bit_cnt_r <= 0;
          right_data_r <= right_data_in;
          shift_r <= left_data_in;
          data_out_r <= left_data_in(data_width_g-1);

        -- Generate lrclk and send the bits from input through shift register to output

        elsif (sync_r = '1' and bclk_fall_r = '1') then

          -- 16 bits sent, switch channel

          if (bit_cnt_r = data_width_g-1) then

            -- On lrclk logic level 0 send bits from right channel

            if (lrclk_r = '1') then
              lrclk_r <= '0';
              bit_cnt_r <= 0;
              shift_r <= right_data_r;
              data_out_r <= right_data_r(data_width_g-1);

            -- On lrclk logic level 1 send bits from left channel

            elsif (lrclk_r = '0') then
              lrclk_r <= '1';
              bit_cnt_r <= 0;
              right_data_r <= right_data_in;
              shift_r <= left_data_in;
              data_out_r <= left_data_in(data_width_g-1);
            end if;
          
          -- Send bits from MSB to LSB (MSB is sent during channel transition already)
          
          else
            data_out_r <= shift_r(data_width_g-2);
            shift_r <= shift_r(data_width_g-2 downto 0) & '0';
            bit_cnt_r <= bit_cnt_r+1;
          end if;
        end if;
      end if;
  end process;

end rtl;
