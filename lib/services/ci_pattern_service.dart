import '../models/poem.dart';
import 'regulated_verse_checker.dart';
import 'rhyme_service.dart';

/// 词谱 DSL 说明
///
/// 1. 词牌名
///    <主词牌名/别名1/别名2>
///    尖括号内为词牌名，斜杠后为别名。
///
/// 2. 体式
///    正体||谱文||
///    变体||谱文||
///    双竖线包裹一个完整体式。一个词牌可有多个体式。
///
/// 3. 分片
///    # 表示上下片或多片之间的分隔。
///
/// 4. 平仄
///    平：该字应为平声。
///    仄：该字应为仄声。
///    中：该字可平可仄。
///
/// 5. 韵脚
///    [1]、[2] 等写在押韵字后面。
///    例如：平平仄[1] 表示最后一个“仄”字押第 1 韵。
///    相同数字属于同一押韵组，必须同韵；不同数字彼此独立，
///    例如 [1]、[2]、[3] 会分别校验各自韵部，不要求互相同韵。
///
/// 6. 叠字 / 叠句
///    {1:平平仄[1]}
///    同编号的大括号内容，要求实际文字完全相同。
///
/// 7. 长句 / 断句不固定
///    (中平中仄中中平仄仄平平[1])
///    小括号内表示：字数和平仄结构固定，但用户文本中的内部断句、
///    标点位置可不固定。
///
/// 8. 同句变体
///    %A=B=C%
///    表示同一句可采用 A、B、C 任一种谱式。等号两侧字数可以不同。
///
/// 9. 标点
///    谱中的 ，。？！；、 用于辅助分句。普通句默认按谱中句读切分；
///    小括号内不强制内部标点。
const String ciPatternSource = '''
<忆秦娥/碧云深/花深深/蓬莱阁/秦楼月/双荷叶>
正体||平中仄[1]，中平中仄{1:平平仄[1]}。{1:平平仄[1]}，中平中仄，中平平仄[1]。#中平中仄平平仄[1]，中平中仄{2:平平仄[1]}。{2:平平仄[1]}，中平中仄，中中平仄[1]。||
变体||平中仄[1]，中平中仄平平仄[1]。平平仄[1]，中平中仄，中平平仄[1]。#中平中仄平平仄[1]，中平中仄平平仄[1]。平平仄[1]，中平中仄，中中平仄[1]。||
变体||平中仄[1]，中平中仄平平仄[1]。平平仄[1]，中平中仄，中平平仄[1]。#中平中仄平平平，中平中仄平平仄[1]。平平仄[1]，中平中仄，中中平仄[1]。||

<水调歌头/元会曲/凯歌>
正体||中中中中仄，中仄仄平平[1]。(中平中仄中中平仄仄平平[1])。中仄中平中仄，中仄中平中仄，中仄仄平平[1]。中中中平仄，中仄仄平平[1]。#中中中，中中仄，仄中平[1]。(中平中仄中中平仄仄平平[1])。中仄中平中仄，中仄中平中仄，中仄仄平平[1]。中仄中平仄，中仄仄平平[1]。||
变体||中中中中仄，中仄仄平平[1]。(中平中仄中中平仄仄平平[1])。中仄中平中仄，中仄中平中仄，中仄仄平平[1]。中中中平仄，中仄仄平平[1]。#中中中，中中仄，仄中平[1]。(中平中仄中中平仄中中仄平平[1])。中仄中平中仄，中仄中平中仄，中仄仄平平[1]。中仄中平仄，中仄仄平平[1]。||
变体||中中中中仄，中仄仄平平[1]。(中平中仄中中平仄仄平平[1])。中仄中平中仄，中仄中平中仄，中仄仄平平[1]。中中中平仄，中仄仄平平[1]。#中中中中仄，仄中平[1]。(中平中仄中中平仄仄平平[1])。中仄中平中仄，中仄中平中仄，中仄仄平平[1]。中仄中平仄，中仄仄平平[1]。||

<八声甘州/甘州/萧萧雨/讌瑶池>
正体||仄中平中仄仄平平，中中仄平平[1]。仄中平中仄，中平中仄，中仄平平[1]。中仄中平中仄，中仄仄平平[1]。中仄中平仄，中仄平平[1]。#中仄中平中仄，仄中平中仄，中仄平平[1]。仄中平中仄，中仄仄平平[1]。仄中中、中平中仄，仄中平、中仄仄平平[1]。平平仄、中平中仄，中仄平平[1]。||
变体||仄平平、平平仄平平，平平仄平平[1]。平平仄仄，平平仄仄，仄仄仄平平[1]。平仄仄平平仄，平仄仄平平[1]。平仄仄平仄，仄仄平平[1]。#仄仄平平仄仄，仄平平仄仄，仄仄平平[1]。仄平平仄仄，平仄仄平平[1]。仄仄平平仄，仄平平仄，仄仄平平[1]。平平仄、平平平仄，平仄平平[1]。||
变体||仄仄平仄仄仄平平，仄平仄平平[1]。平平仄平平仄，仄仄平平[1]。平仄平平仄仄，平仄仄平平[1]。平仄仄平仄，平仄平平[1]。#仄仄仄平仄仄，仄平平仄仄，仄仄平平[1]。仄平平仄仄，仄仄仄平平[1]。仄平平、平平仄仄，仄仄平、平仄仄平平[1]。平平仄、仄平平仄仄，平仄平平[1]。||

<忆江南/望江南/梦江南/江南好>
正体||平中仄，中仄仄平平[1]。中仄中平平仄仄，中平中仄仄平平[1]。中仄仄平平[1]。||
变体||平中仄，中仄仄平平[1]。中仄中平平仄仄，中平中仄仄平平[1]。中仄仄平平[1]。#平中仄，中仄仄平平[1]。中仄中平平仄仄，中平中仄仄平平[1]。中仄仄平平[1]。||
变体||仄仄平平平仄仄[1]。仄仄平平，仄平平仄[1]。中平中仄仄平平[2]。中平中仄仄平平[2]。#中平中仄平平仄[3]。仄仄平平，中仄平平仄[3]。中平中仄仄平平[4]。中平中仄仄平平[4]。||

<浣溪沙/浣溪纱/小庭花/减字浣溪沙/满院春/东风寒/醉木犀/霜菊黄/广寒枝/试香罗/清和风/怨啼鹃>
正体||中仄中平中仄平[1]。中平中仄仄平平[1]。中平中仄仄平平[1]。#中仄中平平仄仄，中平中仄仄平平[1]。中平中仄仄平平[1]。||
变体||中仄中平平仄仄，中平中仄仄平平[1]。中平中仄仄平平[1]。#中仄中平平仄仄，中平中仄仄平平[1]。中平中仄仄平平[1]。||
变体||中仄中平中仄平[1]。中平中仄仄平平[1]。中平中仄仄平平[1]。#中仄中平平仄仄，中平中仄仄平平[1]。仄平平，平仄仄，仄平平[1]。||
变体||中仄中平中仄平[1]。中平中仄仄平平[1]。中仄平，中仄仄，仄平平[1]。#中仄中平平仄仄，中平中仄仄平平[1]。中平平，中仄仄，仄平平[1]。||
变体||中仄中平平仄仄[1]。中平中仄平平仄[1]。中仄中平平仄仄[1]。#中平中仄平平仄[1]。中仄中平平仄仄[1]。中仄中平平仄仄[1]。||

<菩萨蛮>
正体||中平中仄平平仄[1]。中平中仄平平仄[1]。中仄仄平平[2]。%中平平仄平[2]=平平仄仄平[2]%。#中平平仄仄[3]。中仄平平仄[3]。中仄仄平平[4]。%中平平仄平[4]=平平仄仄平[4]%。||
变体||中平中仄平平仄[1]。中平中仄平平仄[1]。中仄仄平平[2]。%中平平仄平[2]=平平仄仄平[2]%。#中平平仄仄[1]。中仄平平仄[1]。中仄仄平平[2]。%中平平仄平[2]=平平仄仄平[2]%。||
变体||中平中仄平平仄[1]。中平中仄平平仄[1]。中仄仄平平[1]。%中平平仄平[1]=平平仄仄平[1]%。#中平平仄仄[2]。中仄平平仄[2]。中仄仄平平[2]。%中平平仄平[2]=平平仄仄平[2]%。||

<卜算子/缺月挂疏桐/百尺楼/楚天遥/眉峰碧>
正体||中仄仄平平，中仄平平仄[1]。中仄中平仄仄平，中仄平平仄[1]。#中仄仄平平，中仄平平仄[1]。中仄中平仄仄平，中仄平平仄[1]。||
变体||中仄平平仄[1]。中仄平平仄[1]。中仄中平仄仄平，中仄平平仄[1]。#中仄平平仄[1]。中仄平平仄[1]。中仄中平仄仄平，中仄平平仄[1]。||
变体||中平中仄平，中仄平平仄[1]。中仄中平仄仄平，中仄平平仄[1]。#中仄平平仄[1]。中仄平平仄[1]。中仄中平仄仄平，中仄仄、中平仄[1]。||
变体||中仄仄平平，中仄平平仄[1]。中仄中平仄仄平，中中仄、中平仄[1]。#中仄仄平平，中仄平平仄[1]。中仄中平仄仄平，中仄平平仄[1]。||
变体||中平中仄平，中仄平平仄[1]。中仄中平仄仄平，中仄仄、中平仄[1]。#中仄平平仄[1]。中仄平平仄[1]。中仄中平仄仄平，中仄仄、中平仄[1]。||
变体||中仄仄平平，中仄平平仄[1]。中仄中平仄仄平，中仄平平仄[1]。#中仄仄平平，中仄平平仄[1]。中仄中平仄仄平，中平中仄平平仄[1]。||

<采桑子/丑奴儿令/罗敷媚歌/丑奴儿/罗敷媚/杨下采桑>
正体||中平中仄平平仄，中仄平平[1]。中仄平平[1]。中仄平平仄仄平[1]。#中平中仄平平仄，中仄平平[1]。中仄平平[1]。中仄平平仄仄平[1]。||
变体||中平中仄平平仄，{1:中仄平平[1]}。{1:中仄平平[1]}。中仄中平、中仄仄平平[1]。#中平中仄平平仄，{2:中仄平平[1]}。{2:中仄平平[1]}。中仄中平、中仄仄平平[1]。||
变体||中平中仄平平仄，中仄平平[1]。中仄平平[1]。中仄平平仄仄平[1]。中仄仄平平[1]。#中平中仄平平仄，中仄平平[1]。中仄平平[1]。中仄平平仄仄平，中仄仄平平[1]。||

<减字木兰花/减兰/木兰香/天下乐令>
正体||中平中仄[1]。中仄中平平仄仄[1]。中仄平平[2]。中仄平平中仄平[2]。#中平中仄[3]。中仄中平平仄仄[3]。中仄平平[4]。中仄平平中仄平[4]。||

<清平乐/清平乐令/忆萝月/醉东风>
正体||中平中仄[1]。中仄平平仄[1]。中仄中平平仄仄[1]。中仄中平中仄[1]。#中平中仄平平[2]。中平中仄平平[2]。中仄中平中仄，中平中仄平平[2]。||
变体||中平中仄[1]。中仄平平仄[1]。中仄中平平仄仄[1]。中中仄、中平仄[1]。#中平中仄平平[2]。中平中仄平平[2]。中仄中平中仄，中平中仄平平[2]。||
变体||中平中仄[1]。中仄平平仄[1]。中仄中平平仄仄[1]。中仄中平中仄[1]。#中仄中仄平平，中仄中平中仄[1]。中仄中平中仄[1]。中仄中平中仄[1]。||

<西江月/白苹香/步虚词/江月令>
正体||中仄中平中仄，中平中仄平平[1]。中平中仄仄平平[1]。中仄中平中仄[1]。#中仄中平中仄，中平中仄平平[1]。中平中仄仄平平[1]。中仄中平中仄[1]。||
变体||中仄中平中仄[1]，中平中仄平平[1]。中平中仄仄平平[1]。中仄中平中仄[1]。#中仄中平中仄[1]，中平中仄平平[1]。中平中仄仄平平[1]。中仄中平中仄[1]。||
变体||中仄中平中仄，中平中仄平平[1]。中平中仄仄平平[1]。中仄中平中仄[1]。#中仄中平中仄，中平中仄平平[2]。中平中仄仄平平[2]。中仄中平中仄[2]。||
变体||中仄中平中仄[1]。中平中仄平平[2]。中平中仄仄平平[2]。中仄中平中仄[1]。#中平中仄平平仄[1]。中平中仄平平[2]。中平中仄仄平平[2]。中仄中平中仄[1]。||
变体||中仄中平中仄，中平中仄平平[1]。中平中仄仄平平[1]。中仄中平，中仄仄平平[1]。#中仄中平中仄，中平中仄平平[1]。中平中仄仄平平[1]。中仄中平，中仄仄平平[1]。||

<浪淘沙令/浪淘沙/曲入冥/卖花声/过龙门/炼丹砂>
正体||中仄仄平平[1]。中仄平平[1]。中平中仄仄平平[1]。中仄中平平仄仄，中仄平平[1]。#中仄仄平平[1]。中仄平平[1]。中平中仄仄平平[1]。中仄中平平仄仄，中仄平平[1]。||
变体||中仄平平[1]。中仄平平[1]。中平中仄仄平平[1]。中仄中平平仄仄，中仄平平[1]。#中仄仄平平[1]。中仄平平[1]。中平中仄仄平平[1]。中仄中平平仄仄，中仄平平[1]。||
变体||中仄平平[1]。中仄平平[1]。中平中仄仄平平[1]。中仄平平，中仄中仄，中仄平平[1]。#中仄仄平平[1]。中仄平平[1]。中平中仄仄平平[1]。中仄中平平仄仄，中仄仄平平[1]。||
变体||中仄平平[1]。中仄平平[1]。中平中仄仄平平[1]。中仄中平平仄仄，中仄平平[1]。#中仄平平[1]。中仄平平[1]。中平中仄仄平平[1]。中仄中平平仄仄，中仄平平[1]。||
变体||中平中仄[1]。中平平仄[1]。中平中仄平平仄[1]。中平平、中仄中仄平仄仄[1]。#中平中仄平平仄[1]。中平平仄[1]。中仄中仄平平仄[1]。中平平、中仄中平仄平仄[1]。||
变体||中仄平仄[1]。中平平仄[1]。中平中仄仄平平，中平中仄，中平中仄，中平平仄[1]。#中仄平平仄[1]。中平平仄[1]。中平中仄仄平平，中平中仄平平仄[1]。中平仄平仄[1]。||

<蝶恋花/鹊踏枝/黄金缕/卷珠帘/明月生南浦/细雨吹池沼/凤栖梧/一箩金/鱼水同欢>
正体||中仄中平平仄仄[1]。中仄平平，中仄平平仄[1]。中仄中平平仄仄[1]。中平中仄平平仄[1]。#中仄中平平仄仄[1]。中仄平平，中仄平平仄[1]。中仄中平平仄仄[1]。中平中仄平平仄[1]。||
变体||中平中仄仄平平[1]。中仄平平，中仄平平仄[1]。中仄中平平仄平[1]。中平中仄平平仄[1]。#中仄中平平仄仄[1]。中仄平平，中仄平平仄[1]。中仄中平平仄仄[1]。中平中仄平平仄[1]。||

<转调蝶恋花>
正体||中仄中平平仄仄[1]。中仄平平，中仄平平仄[1]。中仄平平仄平仄[1]。中平中仄平平仄[1]。#中仄中平平仄仄[1]。中仄平平，中仄平平仄[1]。中仄中平中平仄[1]。中平中仄平平仄[1]。||

<渔家傲>
正体||中仄中平平仄仄[1]。中平中仄平平仄[1]。中仄中平平仄仄[1]。平中仄[1]。中平中仄平平仄[1]。#中仄中平平仄仄[1]。中平中仄平平仄[1]。中仄中平平仄仄[1]。平中仄[1]。中平中仄平平仄[1]。||
变体||中仄中平平仄仄[1]。中平中仄平平仄[1]。中仄中平{1:平仄仄[1]}。{1:平仄仄[1]}。中平中仄平平仄[1]。#中仄中平平仄仄[1]。中平中仄平平仄[1]。中仄中平{2:平仄仄[1]}。{2:平仄仄[1]}。中平中仄平平仄[1]。||
变体||中仄中平仄仄平[1]。中平中仄仄平平[1]。中仄中平平仄仄[1]。平中仄[1]。中平中仄平平仄[1]。#中仄中平仄仄平[1]。中平中仄仄平平[1]。中仄中平平仄仄[1]。平中仄[1]。中平中仄平平仄[1]。||

<满江红>
正体||中仄平平，中中仄、中平中仄[1]。中中仄、中平中仄，中平中仄[1]。中仄中平平仄仄，中平中仄平平仄[1]。仄中平、中仄仄平平，平平仄[1]。#中中仄，平中仄[1]。中中仄，平平仄[1]。(仄中平中仄中中中仄[1])。中仄中平平仄仄，中平中仄平平仄[1]。仄中平、中仄仄平平，平平仄[1]。||
变体||中仄平平，中中仄、平中仄平[1]。中中仄、中平中仄，中仄平平[1]。中仄中平平仄仄，中平中仄仄平平[1]。仄中平、中仄仄平平，平仄平[1]。#中中仄，中仄平[1]。中中仄，仄平平[1]。仄中平中仄，中仄平平[1]。中仄中平平仄仄，中平中仄仄平平[1]。仄中平、中仄仄平平，平仄平[1]。||
变体||中仄平平，中中仄、中平中仄[1]。中中仄、中平中仄，中平中仄[1]。中仄中平平仄仄[1]，中平中仄平平仄[1]。仄中平、中仄仄平平，平平仄[1]。#中中仄，平中仄[1]。中中仄，平平仄[1]。(仄中平中仄中中中仄[1])。中仄中平平仄仄[1]，中平中仄平平仄[1]。仄中平、中仄仄平平，平平仄[1]。||
变体||中仄平平，中中仄、中平中仄[1]。仄中平中仄，中平中仄[1]。中仄中平平仄仄，中平中仄平平仄[1]。仄中平、中仄仄平平，平平仄[1]。#中中仄，平中仄[1]。中中仄，平平仄[1]。(仄中平中仄中中中仄[1])。中仄中平平仄仄，中平中仄平平仄[1]。仄中平、中仄仄平平，平平仄[1]。||
变体||中仄平平，中中仄、中平中仄[1]。中中仄、中平中仄[1]。中仄中平平仄仄，中平中仄平平仄[1]。仄中平、中仄仄平平，平平仄[1]。#中中仄，平中仄[1]。中中仄，平平仄[1]。(仄中平中仄中中中仄[1])。中仄中平平仄仄，中平中仄平平仄[1]。仄中平、中仄仄平平，平平仄[1]。||
变体||中仄平平，中中仄、中平中仄[1]。中中仄、中平中仄，中平中仄[1]。中仄中平平仄仄，中平中仄平平仄[1]。仄中平、中仄仄平平，平平仄[1]。#中中仄，平中仄[1]。中中仄，平平仄[1]。(仄中平中仄中中中仄[1])。(中仄中中平平仄仄)，中平中仄平平仄[1]。仄中平、中仄仄平平，平平仄[1]。||
变体||中仄平平，中中仄、中平中仄[1]。中中仄、中平中仄，中平中仄[1]。中仄中平平仄仄，中平中仄平平仄[1]。仄中平、中仄仄平平，平平仄[1]。#中中仄，平中仄[1]。中中仄，平平仄[1]。(仄中平中仄中中中仄[1])。中仄中平平仄仄，中中平中仄平平仄[1]。仄中平、中仄仄平平，平平仄[1]。||
变体||中仄平平，中中仄、中平中仄[1]。中中仄、中平中中仄，中平中仄[1]。中仄中平平仄仄，中平中仄平平仄[1]。仄中平、中仄仄平平，平平仄[1]。#中中仄，平中仄[1]。中中仄，平平仄[1]。(仄中平中仄中中中仄[1])。中仄中平平仄仄，中平中仄平平仄[1]。仄中平、中仄仄平平，平平仄[1]。||
变体||中仄平平，中中仄、中平中仄[1]。中中仄、中平中仄，中平中仄[1]。(中仄中中平平仄仄)，(中平中中仄平平仄[1])。仄中平、中仄仄平平，平平仄[1]。#中中仄，平中仄[1]。中中仄，平平仄[1]。(仄中平中仄中中中仄[1])。(中仄中中平平仄仄)，(中平中中仄平平仄[1])。仄中平、中仄仄平平，平平仄[1]。||

<念奴娇/大江东去/酹江月/赤壁词/酹月/壶中天慢/大江西上曲/太平欢/寿南枝/古梅曲/湘月/淮甸春/白雪词/百字令/百字谣/无俗念/千秋岁/庆长春/杏花天>
正体||中平中仄，(仄中中中仄中中平仄[1])。中仄中平平仄仄，中仄中平平仄[1]。中仄平平，中平中仄，中仄平平仄[1]。中平中仄，中平中仄中仄[1]。#中中中仄平平，(中平中仄中中平平仄[1])。(中仄中平平仄仄)，中仄中平平仄[1]。中仄平平，(中平中仄中仄平平仄[1])。中平中仄，中平平仄平仄[1]。||
变体||中平中仄，(仄中中中仄中平平仄[1])。中仄中平平仄仄，中仄中平平仄[1]。中仄平平，中平中仄，中仄平平仄[1]。中平中仄，中平中仄中仄[1]。#中中中仄平平，(中平中仄中中平平仄[1])。(中仄中平平仄仄)，中仄中平平仄[1]。中仄平平，(中平中仄中仄平平仄[1])。中平中仄，中平平仄平仄[1]。||
变体||中平中仄，(仄中中中仄中中平仄[1])。中仄中平，中仄仄，中仄中平平仄[1]。中仄平平，中平中仄，中仄平平仄[1]。中平中仄，中平中仄中仄[1]。#中中中仄平平，(中平中仄中中平平仄[1])。(中仄中平中仄仄)，中仄中平平仄[1]。中仄平平，(中平中仄中仄平平仄[1])。中平中仄，中平中仄平仄[1]。||
变体||中平中仄，(仄中中中仄中中平仄[1])。中仄中平平仄仄，中仄中平平仄[1]。中仄平平，中平中仄，中仄平平仄[1]。中平中仄，中平中仄中仄[1]。#中仄[1]。中仄平平，(中平中仄中中平平仄[1])。(中仄中平平仄仄)，中仄中平平仄[1]。中仄平平，(中平中仄中仄平平仄[1])。中平中仄，中平平仄平仄[1]。||
变体||中平中仄[1]，(仄中中中仄中中平仄[1])。中仄中平平仄仄，中仄中平平仄[1]。中仄平平，中平中仄，中仄平平仄[1]。中平中仄，中平中仄中仄[1]。#中中中仄平平，(中平中仄中中平平仄[1])。(中仄中平平仄仄)，中仄中平平仄[1]。中仄平平，(中平中仄中仄平平仄[1])。中平中仄，中平平仄平仄[1]。||
变体||中平中仄[1]，(仄中中中仄中中平仄[1])。中仄中平平仄仄，中仄中平平仄[1]。中仄平平，中平中仄，中仄平平仄[1]。中平中仄，中平中仄中仄[1]。#中仄[1]。中仄平平，(中平中仄中中平平仄[1])。(中仄中平平仄仄)，中仄中平平仄[1]。中仄平平，(中平中仄中仄平平仄[1])。中平中仄，中平平仄平仄[1]。||
变体||中平中仄，(仄中中中仄中中平仄[1])。中仄中平平仄仄，中仄中平平仄[1]。中仄平平，中平中仄，中仄平平仄[1]。中平中仄，中中中平，平仄中仄[1]。#中中中仄平平，(中平中仄中中平平仄[1])。(中仄中平平仄仄)，中仄中平平仄[1]。中仄平平，(中平中仄中仄平平仄[1])。中平中仄，中平平仄平仄[1]。||
变体||中平中仄，(仄中中中仄中中平平[1])。中仄中平平仄仄，中中平仄平平[1]。中仄平平，中平中仄，中仄仄平平[1]。中平中仄，中中中仄平平[1]。#中中中仄平平，(中平中仄中中仄平平[1])。(中仄中平平仄仄)，中仄平仄平平[1]。中仄平平，(中平中仄中仄仄平平[1])。中平中仄，中平中仄平平[1]。||

<长相思/长相思令/相思令/吴山青/山渐青/青山相送迎>
正体||中{1:中平[1]}。仄{1:中平[1]}。中仄平平中仄平[1]。中平中仄平[1]。#中{2:中平[1]}。仄{2:中平[1]}。中仄平平中仄平[1]。中平中仄平[1]。||
变体||中{1:中平[1]}。仄{1:中平[1]}。中仄平平中仄平[1]。中平中仄平[1]。#{2:中中}平。{2:中中}平。中仄平平中仄平[1]。中平中仄平[1]。||
变体||{1:中中平[1]}。{1:中中平[1]}。中仄平平中仄平[1]。中平中仄平[1]。#{1:中中平[1]}。{1:中中平[1]}。中仄平平中仄平[1]。中平中仄平[1]。||
变体||中中平[1]。仄中平[1]。中仄平平中仄平[1]。中平中仄平[1]。#中中平[1]。仄中平[1]。中仄平平中仄平[1]。中平中仄平[1]。||
变体||中中平[1]。仄中平[1]。中仄平平中仄平[1]。中平中仄平[1]。#中中平[2]。仄中平[2]。中仄平平中仄平[2]。中平中仄平[2]。||

<沁园春/洞庭春色/寿星明/东仙>
正体||中中平平，中中中中，中中中平[1]。仄中平中仄，中平中仄，中平中仄，中仄平平[1]。中仄平平，中平中仄，中仄平平中仄平[1]。中平仄，中中平中仄，中仄平平[1]。#中平中仄平平[1]。中中仄、中平中仄平[1]。仄中平中仄，中平中仄，中平中仄，中仄平平[1]。中仄中平，中平中仄，中仄平平中仄平[1]。中中仄，仄中平中仄，中仄平平[1]。||
变体||中中平平，中中中中，中中中平[1]。仄中平中仄，中平中仄，中平中仄，中仄平平[1]。中仄平平，中平中仄，中仄平平中仄平[1]。中平仄，中中平中仄，中仄平平[1]。#中平[1]。中仄平平[1]。(中中仄中平中仄平[1])。仄中平中仄，中平中仄，中平中仄，中仄平平[1]。中仄中平，中平中仄，中仄平平中仄平[1]。中中仄，仄中平中仄，中仄平平[1]。||
变体||中中平平，中中中中，中中中平[1]。仄中平中仄，中平中仄，中平中仄，中仄平平[1]。中仄平平，中平中仄，中仄平平中仄平[1]。中平仄，中中平中仄，中仄平平[1]。#中平[1]。中仄平平[1]。(中中仄中平中仄平[1])。仄中平中仄，中平中仄，中平中仄，中仄平平[1]。中仄中平，中平中仄，中仄仄平平中仄平[1]。中中仄，仄中平中仄，中仄平平[1]。||
变体||中中平平，中中中中，中中中平[1]。仄中平中仄，中平中仄，中中平中仄，中仄平平[1]。中仄平平，中平中仄，中仄平平中仄平[1]。中平仄，中中平中仄，中仄平平[1]。#中平中仄平平[1]。中中仄、中平中仄平[1]。仄中平中仄，中平中仄，中中平中仄，中仄平平[1]。中仄中平，中平中仄，中仄平平中仄平[1]。中中仄，仄中平中仄，中仄平平[1]。||
变体||中中平平，中中中中，中中中平[1]。仄中平中仄，中平中仄，中平中仄，中仄平平[1]。中仄平平，中平中仄，中仄平平中仄平[1]。中平仄，中平中仄，中仄平平[1]。#中平中仄平平[1]。中中仄、中平中仄平[1]。仄中平中仄，中平中仄，中平中仄，中仄平平[1]。中仄中平，中平中仄，中仄平平中仄平[1]。中中仄，中平中仄，中仄平平[1]。||
变体||中中平平，中中中中，中中中平[1]。仄中平中仄，中平中仄，中平中仄，中仄平平[1]。中仄中平平中仄，仄中仄中平平仄平[1]。中平仄，中中平中仄，中仄平平[1]。#中平中仄平平[1]。中中仄、中平中仄平[1]。仄中平中仄，中平中仄，中平中仄，中仄平平[1]。中仄中平平中仄，仄中仄中平平仄平[1]。中中仄，仄中平中仄，中仄平平[1]。||
变体||中中平平，中中中中，中中中平[1]。仄中平中仄，中平中仄，中平中仄，中仄平平[1]。中仄中平平中仄，仄中仄中平平仄平[1]。中平仄，中中平中仄，中仄平平[1]。#中平中仄平平[1]。中中仄平仄平平[1]。仄中平中仄，中平中仄，中平中仄，中仄平平[1]。中仄中平平中仄，(仄中仄中平平仄平[1])。中中仄，仄中平中仄，中仄平平[1]。||

<虞美人/虞美人令/玉壶冰/忆柳曲/一江春水>
正体||中平中仄平平仄[1]，中仄平平中[1]。中平中仄仄平平[2]，(中仄中平中仄仄平平[2])。#中平中仄平平仄[3]，中仄平平中[3]。中平中仄仄平平[4]，(中仄中平中仄仄平平[4])。||
变体||中平中仄平平仄[1]，中仄平平中[1]。中平中仄仄平平[2]，(中仄中平中仄仄平平[2])。#中平中仄平平仄[1]，中仄平平中[1]。中平中仄仄平平[2]，(中仄中平中仄仄平平[2])。||
变体||中平中仄平平仄[1]，中仄平平中[1]。中平中仄仄平平[2]，(中仄中平中仄仄平平[2])。#中平中仄平平仄[1]，中仄平平中[1]。中平中仄仄平平[3]，(中仄中平中仄仄平平[3])。||
变体||中平中仄平平仄[1]，中仄平平中[1]。中平中仄仄平平[2]，中平中仄仄平平[2]。仄平平[2]。#中平中仄平平仄[3]，中仄平平中[3]。中平中仄仄平平[4]，中平中仄仄平平[4]。仄平平[4]。||
变体||中平中仄平平仄[1]，中仄平平中[1]。中平中仄仄平平[2]，中平中仄仄平平[2]。仄平平[2]。#中平中仄平平仄[1]，中仄平平中[1]。中平中仄仄平平[2]，中平中仄仄平平[2]。仄平平[2]。||
变体||中平中仄仄平平[1]，中仄仄平平[1]。中平中仄仄平平[1]，中平中仄仄平平[1]。仄平平[1]。#中平中仄仄平平[2]，中仄仄平平[2]。中平中仄仄平平[2]，中平中仄仄平平[2]。仄平平[2]。||
变体||中平中仄仄平平[1]，中仄仄平平[1]。中平中仄仄平平[1]，中平中仄仄平平[1]。仄平平[1]。#中平中仄平平仄[2]，中仄平平仄[2]。中平中仄仄平平[3]，中平中仄仄平平[3]。仄平平[3]。||

<江城子/江神子/邨意远>
正体||中平中仄仄平平[1]。仄平平[1]，仄中平[1]。中仄平平，中仄仄平平[1]。中仄中平平仄仄，平仄仄，仄平平[1]。||
变体||中平中仄仄平平[1]。仄平平[1]，仄中平[1]。中仄平平，中仄仄平平[1]。中仄中平平仄仄，平仄仄，仄平平[1]。#中平中仄仄平平[1]。仄平平[1]，仄中平[1]。中仄平平，中仄仄平平[1]。中仄中平平仄仄，平仄仄，仄平平[1]。||
变体||中平中仄仄平平[1]。仄平平[1]，仄中平[1]。中仄平平，中仄仄平平[1]。中仄中平平仄仄，平平仄仄，仄平平[1]。||
变体||中平中仄仄平平[1]。平平中仄平[1]，仄中平[1]。中仄平平，中仄仄平平[1]。中仄中平平仄仄，平仄仄，仄平平[1]。||
变体||平平仄，仄平平[1]。平平中仄平[1]，仄中平[1]。中仄平平，中仄仄平平[1]。中仄中平平仄仄，平仄仄，仄平平[1]。||

<破阵子/十拍子>
正体||中仄中平中仄，中平中仄平平[1]。中仄中平平仄仄，中仄平平中仄平[1]。中平中仄平[1]。#中仄中平中仄，中平中仄平平[1]。中仄中平平仄仄，中仄平平中仄平[1]。中平中仄平[1]。||

<如梦令/忆仙姿/宴桃源/不见/比梅/梅苑/古记/鸣鹤余音/无梦令/如意令>
正体||中仄中平中仄[1]。中仄中平中仄[1]。中仄仄平平，中仄中平中仄[1]。{1:中仄[1]}。{1:中仄[1]}。中仄中平中仄[1]。||
变体||中仄中平中仄[1]。中仄中平中仄[1]。中仄仄平平，中仄中平中仄[1]。中仄[1]。中仄[1]。中仄中平中仄[1]。||
变体||中仄中平中仄[1]。中仄中平中仄[1]。中仄仄平平，中仄中平中仄[1]。中{1:仄[1]}。中{1:仄[1]}。中仄中平中仄[1]。||
变体||中仄中平中仄[1]。中仄中平中仄[1]。中仄仄平平，中仄{1:中平中仄[1]}。{1:中平中仄[1]}。中仄中平中仄[1]。||
变体||中仄中平中仄[1]。中仄中平中仄[1]。中仄仄平平，中仄中平中仄[1]。{1:中仄[1]}。{1:中仄[1]}。中仄中平中仄[1]。#中仄中平中仄[1]。中仄中平中仄[1]。中仄仄平平，中仄中平中仄[1]。{1:中仄[1]}。{1:中仄[1]}。中仄中平中仄[1]。||

<南乡子>
正体||仄仄平平[1]。中中中中仄中平[1]。中仄中平平中仄[2]。平仄[2]。中仄中平平中仄[2]。||
变体||仄仄平平[1]。中中中中仄中平[1]。中仄中平平中仄[2]。平平仄[2]。中仄中平平中仄[2]。||
变体||中仄仄平平[1]。中中中中仄中平[1]。中仄中平平中仄[2]。平仄[2]。中仄中平平中仄[2]。||
变体|中仄仄平平[1]。中仄平平仄中平[1]。中仄中平平中仄。平平[1]。中仄中平仄仄平[1]。#中仄仄平平[1]。中仄平平仄中平[1]。中仄中平平中仄。平平[1]。中仄中平仄仄平[1]。||

<定风波/定风流/定风波令>
正体||中仄平平中仄平[1]。中平中仄仄平平[1]。中仄中平平中仄[2]。中仄[2]。中平中仄仄平平[1]。#中仄中平平仄仄[3]。中仄[3]。中平中仄仄平平[1]。中仄中平平仄仄[4]。中仄[4]。中平中仄仄平平[1]。||
变体||中仄平平中仄平[1]。中平中仄仄平平[1]。中仄中平平中仄[2]。中仄[2]。中平中仄仄平平[1]。#中仄中平平仄仄[3]。中仄[3]。中平中仄仄平平[1]。中仄中平平仄仄[4]。中仄[4]。中平中中仄仄平平[1]。||
变体||中仄平平中仄仄。中平中仄仄平平[1]。中仄中平平中仄[2]。中仄[2]。中平中仄仄平平[1]。#中仄中平平仄仄。中仄[3]。中平中仄仄平平[1]。中仄中平平仄仄[4]。中仄[4]。中平中仄仄平平[1]。||
变体||中仄平平中仄平[1]。中平中仄仄平平[1]。中仄中平平中仄。中仄。中平中仄仄平平[1]。#中仄中平平仄仄。中仄。中平中仄仄平平[1]。中仄中平平仄仄。中仄。中平中仄仄平平[1]。||

<钗头凤/撷芳词/摘红英>
正体||中平仄[1]。中中仄[1]。仄平中中平中仄[1]。平中仄[2]。中平仄[2]。仄中平中，仄中平仄[2]。{1:仄[2]}。{1:仄[2]}。{1:仄[2]}。#平中仄[1]。中平仄[1]。中平中仄中平仄[1]。平平仄[2]。中平仄[2]。平中平中，仄平平仄[2]。{2:仄[2]}。{2:仄[2]}。{2:仄[2]}。||
变体||中平仄[1]。中中仄[1]。仄平中中平中仄[1]。仄中平[2]。仄平平[2]。仄中平中，中中平平[2]。{3:平[2]}。{3:平[2]}。{3:平[2]}。#平中仄[1]。中平仄[1]。中平中仄中平仄[1]。仄平平[2]。仄平平[2]。仄中中中，中仄平平[2]。{4:平[2]}。{4:平[2]}。{4:平[2]}。||
变体||中平仄[1]。中中仄[1]。仄平中中平中仄[1]。平中仄[2]。中平仄[2]。仄仄平中，仄平平仄[2]。#平中仄[1]。中平仄[1]。中平中仄中平仄[1]。平平仄[2]。中平仄[2]。中中中中，仄平中仄[2]。||

<鹧鸪天/思越人/思佳客/剪朝霞/骊歌一叠/醉梅花>
正体||中仄平平中仄平[1]。中平中仄仄平平[1]。中平中仄中平仄，中仄平平中仄平[1]。#中中仄，仄平平[1]。中平中仄仄平平[1]。中平中仄平平仄，中仄平平中仄平[1]。||

<临江仙/谢新恩/雁后归/画屏春/庭院深深>
正体||%中中中中平中仄=中中中中仄平仄%，中平中仄平平[1]。中平中仄仄平平[1]。中平中仄仄，中仄仄平平[1]。#%中中中中平中仄=中中中中仄平仄%，中平中仄平平[1]。中平中仄仄平平[1]。中平中仄仄，中仄仄平平[1]。||
变体||%中中中中平中仄=中中中中仄平仄%，中平中仄平平[1]。中平中仄仄平平[1]。中平中仄，中仄仄平平[1]。#%中中中中平中仄=中中中中仄平仄%，中平中仄平平[1]。中平中仄仄平平[1]。中平中仄，中仄仄平平[1]。||  
变体||%中中中中平中仄=中中中中仄平仄%，中平中仄平平[1]。中平中仄仄平平[1]。中平中仄仄，中仄仄平平[1]。#%中中中中平中仄=中中中中仄平仄%，中平中仄平平[2]。中平中仄仄平平[2]。中平中仄仄，中仄仄平平[2]。||  

<永遇乐/永遇乐慢/消息>
正体||中仄平平，中平中仄，中中平仄[1]。中仄平平，中平中仄，中仄平平仄[1]。(中平中仄中平中仄中仄中平中仄[1])。(中平中平平中仄中中仄中平仄[1])。#中平中仄，(中中中中中仄中平中仄[1])。(中仄平平中平中仄中仄平平仄[1])。(中平中仄中平中仄中仄中中中仄[1])。中中中、中中中仄，中平仄仄[1]。||
变体||中仄平平，中平中仄，中中平仄[1]。中仄平平，中平中仄，中仄平平仄[1]。(中平中仄中平中仄中仄中平中仄[1])。(中平中仄中平仄中仄平中仄[1])。#(中平中中中中中仄中仄中平中仄[1])。(中仄平平中平中仄中仄平平仄[1])。(中平中仄中平中仄中仄中中中仄[1])。中中中、中中中仄，中平仄仄[1]。||
变体||中仄平平，中平中仄，中中平平[1]。中仄平平，中平中仄，中仄平仄平[1]。(中平中仄中平中仄中平中仄中平[1])。(中平中平平中仄中中仄仄平平[1])。#中平中仄，(中中中中中仄中平中仄[1])。(中仄平平中平中仄中平仄中平[1])。(中平中仄中平中仄中平中中中平[1])。中中中、中中中仄，中平仄平[1]。||

<青玉案/西湖路>
正体||中平中仄平平仄[1]。(仄仄中平平仄[1])。中仄中平平仄仄[1]。中平中仄，中平中仄，中仄平平仄[1]。#中平中仄平平仄[1]，%中仄中中中平仄[1]=(中仄中仄平仄[1])%。中仄中平平仄仄[1]。中平中仄，中平中仄，中仄平平仄[1]。||  
变体||中平中仄平平仄[1]。(仄仄中平平仄[1])。中仄中平平仄仄[1]。中平中仄，中平中仄，中仄平平仄[1]。#中平中仄平平仄[1]，(中中中平平仄平仄[1])。中仄中平平仄仄[1]。中平中仄，中平中仄，中仄平平仄[1]。|| 
变体||中平中仄平平仄[1]。中仄中中中平仄[1]。中仄中平平仄仄[1]。中平中仄，中平中仄，中仄平平仄[1]。#中平中仄平平仄[1]，中仄中平仄平仄[1]。中仄中平平仄仄[1]。中平中仄，中平中仄，中仄平平仄[1]。||  
变体||中平中仄平平仄[1]。中仄中中中平仄[1]。中仄中平平仄仄[1]。中平中仄，中平中仄，中仄平平仄[1]。#中平中仄平平仄[1]，(中仄中平平仄平仄[1])。中仄中平平仄仄[1]。中平中仄，中平中仄，中仄平平仄[1]。|| 
变体||中平中仄平平仄[1]。(仄仄平平仄[1])。中仄中平平仄仄[1]。中平中仄，中平中仄，中仄平平仄[1]。#中平中仄平平仄[1]，%中仄中中中平仄[1]=(中仄中仄平仄[1])%。中仄中平平仄仄[1]。中平中仄，中平中仄，中仄平平仄[1]。||  
变体||中平中仄平平仄[1]。中仄中中中平仄[1]。中仄中平平仄仄[1]。中仄中平中仄仄，中平中仄中平平，(中中仄平平仄[1])。#中平中仄平平仄[1]，中仄中平仄平仄[1]。中仄中平平仄仄[1]。中平中仄，中平中仄，中仄平平仄[1]。||  

<望海潮>
正体||中平平仄，中平中仄，中平中仄平平[1]。平仄仄平，平平仄仄，中平中仄平平[1]。中仄仄平平[1]。仄中中中仄，中仄平平[1]。中仄平平，(中中中仄仄平平[1])。#中平中仄平平[1]。仄中平中仄，中仄平平[1]。平仄仄平，平平仄仄，中平中仄平平[1]。中仄仄平平[1]。中中平中仄，中仄平平[1]。中仄平平中仄，中仄仄平平[1]。||
变体||中平平仄，平平中仄，中平中仄平平[1]。平仄仄平，平平仄仄，中平中仄平平[1]。中仄仄平平[1]。仄中中中仄，中仄平平[1]。中仄平平，中中中仄仄平平[1]。#中平中仄平平[1]。仄中平仄仄，中仄平平[1]。平仄仄平，平平仄仄，中平中仄平平[1]。中仄仄平平[1]。中中平中仄，中仄平平[1]。中仄平平，中中中仄仄平平[1]。||
变体||中平平仄，中平中仄，中平中仄平平[1]。平仄仄平，平平仄仄，中平中仄平平[1]。中仄仄平平[1]。仄中中中仄，中仄平平[1]。中仄平平，(中中中仄仄平平[1])。#中平[1]。中仄平平[1]。仄中平中仄，中仄平平[1]。平仄仄平，平平仄仄，中平中仄平平[1]。中仄仄平平[1]。中中平中仄，中仄平平[1]。中仄平平中仄，中仄仄平平[1]。||

<桂枝香/疏帘淡月>
正体||中平中仄[1]。仄中仄中平中中平仄[1]。中仄平平仄仄，仄平平仄[1]。中平中仄平平仄，仄平平、中中平仄[1]。仄平平仄，中平中仄，中平平仄[1]。#仄中中、平平仄仄[1]。仄中仄平中，中中平仄[1]。中仄平平，中仄仄平平仄[1]。中平中仄平平仄，仄平平中中平仄[1]。中平中仄，中平中中，仄平平仄[1]。||
变体||中平中仄[1]。(仄中中中平中中平仄[1])。中仄平平，中仄仄平平仄[1]。中平中仄平平仄，仄平平、中中平仄[1]。仄平平仄，中平中仄，中平平仄[1]。#仄中中、平平仄仄[1]。中仄平平，中仄仄平平仄[1]。中仄平平，中仄仄平平仄[1]。中平中仄平平仄，仄平平中中平仄[1]。中平中仄，中平中中，仄平平仄[1]。||

<天净沙/塞上秋>
正体||中中中仄平平[1]。仄平平仄平平[1]。仄仄平平仄中[1]。中平中仄[1]。仄平平仄平平[1]。||

<相见欢/秋夜月/上西楼/西楼子/忆真妃/月上瓜州/乌夜啼>
正体||中平中仄平平[1]。仄平平[1]。中仄中平中仄、仄平平[1]。#中中仄[2]。中中仄[2]。仄平平[1]。(中仄中平中仄仄平平[1]。)||
变体||中平中仄平平[1]。仄平平[1]。中仄中平中仄、仄平平[1]。#中中仄[1]。中中仄[1]。仄平平[1]。(中仄中平中仄仄平平[1]。)||
变体||中平中仄平平[1]。仄平平[1]。中仄中平中仄、仄平平[1]。#中中仄。中中仄。仄平平[1]。(中仄中平中仄仄平平[1]。)||
变体||中平中仄平平[1]。仄平平[1]。中仄中平中仄、仄平平[1]。#中中中中中仄，仄平平[1]。(中仄中平中仄仄平平[1]。)||
变体||中平中仄平平[1]。仄平平[1]。中仄中平中仄、仄平平[1]。#中中仄。中中平[1]。仄平平[1]。(中仄中平中仄仄平平[1]。)||
''';

class CiPatternCheck {
  const CiPatternCheck({
    required this.applicable,
    required this.supportedPattern,
    required this.unresolved,
    required this.ok,
    required this.tuneName,
    required this.variantLabel,
    required this.displayForm,
    required this.primaryRhyme,
    required this.summary,
    required this.details,
    required this.lines,
    this.suppressPanel = false,
  });

  final bool applicable;
  final bool supportedPattern;
  final bool unresolved;
  final bool ok;
  final String tuneName;
  final String variantLabel;
  final String displayForm;
  final String primaryRhyme;
  final String summary;
  final List<String> details;
  final List<CiPatternLineCheck> lines;
  final bool suppressPanel;
}

class CiPatternLineCheck {
  const CiPatternLineCheck({
    required this.lineNumber,
    required this.marks,
  });

  final int lineNumber;
  final List<RegulatedVerseMark> marks;
}

CiPatternCheck checkCiPattern(Poem poem) {
  if (!poem.prosodySupported ||
      !poem.prosodyEnabled ||
      poem.prosodySystem != Poem.prosodySystemCi) {
    return const CiPatternCheck(
      applicable: false,
      supportedPattern: false,
      unresolved: false,
      ok: false,
      tuneName: '',
      variantLabel: '',
      displayForm: '',
      primaryRhyme: '',
      summary: '当前作品暂不进行词谱审查。',
      details: <String>[],
      lines: <CiPatternLineCheck>[],
    );
  }

  final registry = _CiPatternRegistry.instance;
  final tune = registry.findByName(poem.prosodyForm.trim()) ??
      registry.findByTitle(_normalizeTitle(poem.title));
  if (tune == null) {
    final tuneName = poem.prosodyForm.trim();
    return CiPatternCheck(
      applicable: true,
      supportedPattern: false,
      unresolved: false,
      ok: false,
      tuneName: tuneName,
      variantLabel: '',
      displayForm: tuneName.isEmpty ? '词谱暂未接入' : tuneName,
      primaryRhyme: '',
      summary: tuneName.isEmpty
          ? '暂不支持该词牌的格律审查。'
          : '暂不支持《$tuneName》的格律审查。',
      details: const <String>[
        '该词牌已在词牌库中识别，但本地词谱暂未接入；在 ciPatternSource 添加词谱后即可自动启用。',
      ],
      lines: const <CiPatternLineCheck>[],
    );
  }

  final actual = _parseActualContent(poem);
  if (actual.isEmpty) {
    return CiPatternCheck(
      applicable: true,
      supportedPattern: true,
      unresolved: true,
      ok: false,
      tuneName: tune.primaryName,
      variantLabel: '',
      displayForm: '${tune.primaryName}候选',
      primaryRhyme: '',
      summary: '正文尚不能进行词谱审查。',
      details: const <String>['请先确认正文内容。'],
      lines: const <CiPatternLineCheck>[],
    );
  }

  final matches = <_CiVariantMatch>[];
  for (var index = 0; index < tune.variants.length; index += 1) {
    matches.add(
      _compareVariant(
        poem: poem,
        tune: tune,
        variant: tune.variants[index],
        variantOrder: index,
        actualClauses: actual,
      ),
    );
  }
  matches.sort();
  final best = matches.first;
  if (_shouldSuppressLikelyNonCi(tune, best)) {
    return CiPatternCheck(
      applicable: false,
      supportedPattern: false,
      unresolved: false,
      ok: false,
      tuneName: tune.primaryName,
      variantLabel: '',
      displayForm: '',
      primaryRhyme: '',
      summary: '当前作品暂不进行词谱审查。',
      details: const <String>[],
      lines: const <CiPatternLineCheck>[],
      suppressPanel: true,
    );
  }
  return best.toCheck();
}

bool _shouldSuppressLikelyNonCi(_CiTunePattern tune, _CiVariantMatch match) {
  if (match.errorCount <= 8) {
    return false;
  }
  const suppressibleTuneNames = {
    '长相思',
    '浪淘沙',

  };
  return tune.names.any(suppressibleTuneNames.contains);
}

bool hasCiPatternForTune(String tuneName) {
  return _CiPatternRegistry.instance.findByName(tuneName) != null;
}

Set<String> supportedCiPatternTuneNames() {
  return _CiPatternRegistry.instance.allNames;
}

class _CiPatternRegistry {
  _CiPatternRegistry._(this.tunes);

  static final _CiPatternRegistry instance =
      _CiPatternRegistry._(_parseCiPatternSource(ciPatternSource));

  final List<_CiTunePattern> tunes;

  Set<String> get allNames => {
        for (final tune in tunes) ...tune.names,
      };

  _CiTunePattern? findByName(String name) {
    final normalized = _normalizeTitle(name);
    if (normalized.isEmpty) {
      return null;
    }
    for (final tune in tunes) {
      if (tune.names.contains(normalized)) {
        return tune;
      }
    }
    return null;
  }

  _CiTunePattern? findByTitle(String title) {
    final normalized = _normalizeTitle(title);
    final names = allNames.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final name in names) {
      if (normalized == name ||
          normalized.startsWith('$name·') ||
          normalized.startsWith('$name•') ||
          normalized.startsWith('$name・')) {
        return findByName(name);
      }
    }
    return null;
  }
}

class _CiTunePattern {
  const _CiTunePattern({
    required this.names,
    required this.variants,
  });

  final List<String> names;
  final List<_CiPatternVariant> variants;

  String get primaryName => names.first;
}

class _CiPatternVariant {
  const _CiPatternVariant({
    required this.label,
    required this.clauses,
  });

  final String label;
  final List<_PatternClause> clauses;
}

class _PatternClause {
  const _PatternClause({
    required this.partIndex,
    required this.flexibleBreaks,
    required this.alternatives,
  });

  final int partIndex;
  final bool flexibleBreaks;
  final List<_PatternAlternative> alternatives;
}

class _PatternAlternative {
  const _PatternAlternative(this.tokens);

  final List<_PatternToken> tokens;
}

class _PatternToken {
  const _PatternToken({
    required this.tone,
    this.rhymeGroup,
    this.repeatGroup,
  });

  final String tone;
  final String? rhymeGroup;
  final String? repeatGroup;
}

class _ActualClause {
  const _ActualClause({
    required this.partIndex,
    required this.lineNumber,
    required this.characters,
  });

  final int partIndex;
  final int lineNumber;
  final List<_ActualCharacter> characters;
}

class _ActualCharacter {
  const _ActualCharacter({
    required this.character,
    required this.tone,
    required this.charIndex,
    required this.lineNumber,
  });

  final String character;
  final String tone;
  final int charIndex;
  final int lineNumber;
}

class _RhymeFootMatch {
  const _RhymeFootMatch({
    required this.group,
    required this.character,
    required this.charIndex,
    required this.lineNumber,
  });

  final String group;
  final String character;
  final int charIndex;
  final int lineNumber;
}

class _CiVariantMatch implements Comparable<_CiVariantMatch> {
  _CiVariantMatch({
    required this.tune,
    required this.variant,
    required this.variantOrder,
    required this.errorCount,
    required this.unresolvedCount,
    required this.specificityScore,
    required this.primaryRhyme,
    required this.lineMarks,
    required this.details,
  });

  final _CiTunePattern tune;
  final _CiPatternVariant variant;
  final int variantOrder;
  final int errorCount;
  final int unresolvedCount;
  final int specificityScore;
  final String primaryRhyme;
  final Map<int, List<RegulatedVerseMark>> lineMarks;
  final List<String> details;

  bool get ok => errorCount == 0 && unresolvedCount == 0;
  bool get unresolved => unresolvedCount > 0;

  CiPatternCheck toCheck() {
    final lines = [
      for (final entry in lineMarks.entries)
        CiPatternLineCheck(
          lineNumber: entry.key,
          marks: List.unmodifiable(entry.value),
        ),
    ];
    lines.sort((a, b) => a.lineNumber.compareTo(b.lineNumber));
    final displayForm = unresolved
        ? '${tune.primaryName}候选'
        : ok
            ? '合谱·${variant.label}'
            : '非正格';
    final checkDetails = <String>[
      if (!ok) '最接近：${tune.primaryName}·${variant.label}。',
      ...details,
    ];
    return CiPatternCheck(
      applicable: true,
      supportedPattern: true,
      unresolved: unresolved,
      ok: ok,
      tuneName: tune.primaryName,
      variantLabel: variant.label,
      displayForm: displayForm,
      primaryRhyme: primaryRhyme,
      summary: unresolved
          ? '仍有多音或未知字未确认，暂只显示逐字平仄。'
          : ok
              ? '词谱审查通过，$displayForm。'
              : '检测到非正格。如有需求，建议和智能体讨论本词格律情况。',
      details: List.unmodifiable(checkDetails),
      lines: List.unmodifiable(lines),
    );
  }

  @override
  int compareTo(_CiVariantMatch other) {
    final errorCompare = errorCount.compareTo(other.errorCount);
    if (errorCompare != 0) {
      return errorCompare;
    }
    final unresolvedCompare = unresolvedCount.compareTo(other.unresolvedCount);
    if (unresolvedCompare != 0) {
      return unresolvedCompare;
    }
    final specificityCompare =
        other.specificityScore.compareTo(specificityScore);
    if (specificityCompare != 0) {
      return specificityCompare;
    }
    final labelCompare = _variantLabelRank(
      variant.label,
    ).compareTo(_variantLabelRank(other.variant.label));
    if (labelCompare != 0) {
      return labelCompare;
    }
    return variantOrder.compareTo(other.variantOrder);
  }
}

int _variantLabelRank(String label) {
  return label.trim() == '正体' ? 0 : 1;
}

List<_CiTunePattern> _parseCiPatternSource(String source) {
  final tunes = <_CiTunePattern>[];
  final tuneExp = RegExp(r'<([^>]+)>([\s\S]*?)(?=\n<|$)');
  for (final tuneMatch in tuneExp.allMatches(source)) {
    final names = tuneMatch
        .group(1)!
        .split('/')
        .map(_normalizeTitle)
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    final body = tuneMatch.group(2)!;
    final variants = <_CiPatternVariant>[];
    final variantExp = RegExp(r'([^\s|]+)\|\|([\s\S]*?)\|\|');
    for (final variantMatch in variantExp.allMatches(body)) {
      variants.add(
        _CiPatternVariant(
          label: variantMatch.group(1)!.trim(),
          clauses: _parsePatternClauses(variantMatch.group(2)!.trim()),
        ),
      );
    }
    if (names.isNotEmpty && variants.isNotEmpty) {
      tunes.add(_CiTunePattern(names: names, variants: variants));
    }
  }
  return List.unmodifiable(tunes);
}

List<_PatternClause> _parsePatternClauses(String body) {
  final clauses = <_PatternClause>[];
  var partIndex = 0;
  final buffer = StringBuffer();
  var braceDepth = 0;
  var parenDepth = 0;
  var bracketDepth = 0;
  var inAlternatives = false;

  void flush() {
    final raw = buffer.toString().trim();
    buffer.clear();
    if (raw.isEmpty) {
      return;
    }
    clauses.add(_parsePatternClause(raw, partIndex));
  }

  for (final rune in body.runes) {
    final char = String.fromCharCode(rune);
    if (char == '%' && braceDepth == 0 && parenDepth == 0 && bracketDepth == 0) {
      inAlternatives = !inAlternatives;
      buffer.write(char);
      continue;
    }
    if (char == '{') braceDepth += 1;
    if (char == '}') braceDepth -= 1;
    if (char == '(') parenDepth += 1;
    if (char == ')') parenDepth -= 1;
    if (char == '[') bracketDepth += 1;
    if (char == ']') bracketDepth -= 1;

    if (char == '#' &&
        braceDepth == 0 &&
        parenDepth == 0 &&
        bracketDepth == 0 &&
        !inAlternatives) {
      flush();
      partIndex += 1;
      continue;
    }
    if (_isSentencePunctuation(char) &&
        braceDepth == 0 &&
        parenDepth == 0 &&
        bracketDepth == 0 &&
        !inAlternatives) {
      flush();
      continue;
    }
    buffer.write(char);
  }
  flush();
  return List.unmodifiable(clauses);
}

_PatternClause _parsePatternClause(String raw, int partIndex) {
  var text = raw.trim();
  var flexible = false;
  if (text.startsWith('(') && text.endsWith(')')) {
    flexible = true;
    text = text.substring(1, text.length - 1).trim();
  }

  final alternatives = <String>[];
  if (text.startsWith('%') && text.endsWith('%')) {
    alternatives.addAll(text.substring(1, text.length - 1).split('='));
  } else {
    alternatives.add(text);
  }
  return _PatternClause(
    partIndex: partIndex,
    flexibleBreaks: flexible,
    alternatives: [
      for (final alternative in alternatives)
        _PatternAlternative(_parsePatternTokens(alternative.trim())),
    ],
  );
}

List<_PatternToken> _parsePatternTokens(String text, {String? repeatGroup}) {
  final tokens = <_PatternToken>[];
  for (var i = 0; i < text.length; i += 1) {
    final char = text[i];
    if (char == '{') {
      final end = _findMatching(text, i, '{', '}');
      if (end < 0) {
        continue;
      }
      final inner = text.substring(i + 1, end);
      final colon = inner.indexOf(':');
      if (colon > 0) {
        final group = inner.substring(0, colon).trim();
        final pattern = inner.substring(colon + 1);
        tokens.addAll(_parsePatternTokens(pattern, repeatGroup: group));
      }
      i = end;
      continue;
    }
    if (char != '平' && char != '仄' && char != '中') {
      continue;
    }

    String? rhymeGroup;
    if (i + 1 < text.length && text[i + 1] == '[') {
      final end = text.indexOf(']', i + 2);
      if (end > i) {
        rhymeGroup = text.substring(i + 2, end).trim();
        i = end;
      }
    }
    tokens.add(
      _PatternToken(
        tone: char,
        rhymeGroup: rhymeGroup,
        repeatGroup: repeatGroup,
      ),
    );
  }
  return List.unmodifiable(tokens);
}

int _findMatching(String text, int start, String open, String close) {
  var depth = 0;
  for (var i = start; i < text.length; i += 1) {
    if (text[i] == open) depth += 1;
    if (text[i] == close) {
      depth -= 1;
      if (depth == 0) {
        return i;
      }
    }
  }
  return -1;
}

List<_ActualClause> _parseActualContent(Poem poem) {
  final toneLines = {
    for (final line in analyzeCharacterTones(poem)) line.lineNumber: line,
  };
  final clauses = <_ActualClause>[];
  final rawLines = poem.content
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  var partIndex = 0;
  var lineNumber = 0;
  var previousWasBlank = false;

  for (final rawLine in rawLines) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      if (!previousWasBlank && clauses.isNotEmpty) {
        partIndex += 1;
      }
      previousWasBlank = true;
      continue;
    }
    previousWasBlank = false;
    lineNumber += 1;
    final toneLine = toneLines[lineNumber];
    final current = <_ActualCharacter>[];
    var charIndex = 0;
    for (final rune in line.runes) {
      final char = String.fromCharCode(rune);
      if (_isChineseRune(rune)) {
        final tone = toneLine != null && charIndex < toneLine.characters.length
            ? toneLine.characters[charIndex].mark
            : '?';
        current.add(
          _ActualCharacter(
            character: char,
            tone: tone,
            charIndex: charIndex + 1,
            lineNumber: lineNumber,
          ),
        );
        charIndex += 1;
      } else if (_isSentencePunctuation(char)) {
        if (current.isNotEmpty) {
          clauses.add(
            _ActualClause(
              partIndex: partIndex,
              lineNumber: lineNumber,
              characters: List.unmodifiable(current),
            ),
          );
          current.clear();
        }
      }
    }
    if (current.isNotEmpty) {
      clauses.add(
        _ActualClause(
          partIndex: partIndex,
          lineNumber: lineNumber,
          characters: List.unmodifiable(current),
        ),
      );
    }
  }
  return List.unmodifiable(clauses);
}

_CiVariantMatch _compareVariant({
  required Poem poem,
  required _CiTunePattern tune,
  required _CiPatternVariant variant,
  required int variantOrder,
  required List<_ActualClause> actualClauses,
}) {
  var actualIndex = 0;
  var errorCount = 0;
  var unresolvedCount = 0;
  var specificityScore = 0;
  final lineMarks = <int, List<RegulatedVerseMark>>{};
  final details = <String>[];
  final repeatTexts = <String, _RepeatText>{};
  final rhymeFeet = <_RhymeFootMatch>[];

  void addMark(int lineNumber, RegulatedVerseMark mark) {
    lineMarks.putIfAbsent(lineNumber, () => <RegulatedVerseMark>[]).add(mark);
  }

  for (final clause in variant.clauses) {
    if (actualIndex >= actualClauses.length) {
      errorCount += 1;
      details.add('正文句数少于词谱。');
      continue;
    }
    final best = _matchBestAlternative(
      clause: clause,
      actualClauses: actualClauses,
      startIndex: actualIndex,
    );
    actualIndex = best.nextIndex;
    errorCount += best.errorCount;
    unresolvedCount += best.unresolvedCount;
    specificityScore += best.specificityScore;
    details.addAll(best.details);
    for (final mark in best.marks) {
      addMark(mark.key, mark.value);
    }

    for (final repeat in best.repeatTexts.entries) {
      final existing = repeatTexts[repeat.key];
      if (existing == null) {
        repeatTexts[repeat.key] = repeat.value;
      } else if (existing.text != repeat.value.text) {
        errorCount += 1;
        details.add(
          '叠句不一致：第 ${repeat.value.lineNumber} 行“${repeat.value.text}”'
          '应与前处“${existing.text}”相同。',
        );
      }
    }
    rhymeFeet.addAll(best.rhymeFeet);
  }

  if (actualIndex < actualClauses.length) {
    for (var i = actualIndex; i < actualClauses.length; i += 1) {
      errorCount += 1;
      details.add(
        '正文多出词谱之外的句读：第 ${actualClauses[i].lineNumber} 行'
        '“${_actualCharactersText(actualClauses[i].characters)}”。',
      );
    }
  }

  final rhymeResult = _checkRhymeGroups(
    poem: poem,
    feet: rhymeFeet,
  );
  errorCount += rhymeResult.errorCount;
  unresolvedCount += rhymeResult.unresolvedCount;
  specificityScore += rhymeResult.distinctRhymeScore;
  details.addAll(rhymeResult.details);
  for (final mark in rhymeResult.marks) {
    addMark(mark.key, mark.value);
  }

  return _CiVariantMatch(
    tune: tune,
    variant: variant,
    variantOrder: variantOrder,
    errorCount: errorCount,
    unresolvedCount: unresolvedCount,
    specificityScore: specificityScore,
    primaryRhyme: rhymeResult.primaryRhyme,
    lineMarks: lineMarks,
    details: details,
  );
}

class _LineMarkEntry {
  const _LineMarkEntry(this.key, this.value);

  final int key;
  final RegulatedVerseMark value;
}

class _RepeatText {
  const _RepeatText({
    required this.text,
    required this.lineNumber,
    required this.charCount,
  });

  final String text;
  final int lineNumber;
  final int charCount;
}

class _ClauseMatch {
  const _ClauseMatch({
    required this.nextIndex,
    required this.errorCount,
    required this.unresolvedCount,
    required this.specificityScore,
    required this.marks,
    required this.details,
    required this.repeatTexts,
    required this.rhymeFeet,
  });

  final int nextIndex;
  final int errorCount;
  final int unresolvedCount;
  final int specificityScore;
  final List<_LineMarkEntry> marks;
  final List<String> details;
  final Map<String, _RepeatText> repeatTexts;
  final List<_RhymeFootMatch> rhymeFeet;

  int get score => errorCount * 100 + unresolvedCount;
}

_ClauseMatch _matchBestAlternative({
  required _PatternClause clause,
  required List<_ActualClause> actualClauses,
  required int startIndex,
}) {
  final matches = <_ClauseMatch>[
    for (final alternative in clause.alternatives)
      _matchAlternative(
        clause: clause,
        alternative: alternative,
        actualClauses: actualClauses,
        startIndex: startIndex,
      ),
  ]..sort((a, b) {
      final scoreCompare = a.score.compareTo(b.score);
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      return b.specificityScore.compareTo(a.specificityScore);
    });
  return matches.first;
}

_ClauseMatch _matchAlternative({
  required _PatternClause clause,
  required _PatternAlternative alternative,
  required List<_ActualClause> actualClauses,
  required int startIndex,
}) {
  final consumed = <_ActualClause>[];
  var nextIndex = startIndex;
  var charCount = 0;
  final targetLength = alternative.tokens.length;
  while (nextIndex < actualClauses.length) {
    final current = actualClauses[nextIndex];
    if (current.partIndex != clause.partIndex) {
      break;
    }
    consumed.add(current);
    charCount += current.characters.length;
    nextIndex += 1;
    if (!clause.flexibleBreaks || charCount >= targetLength) {
      break;
    }
  }

  if (consumed.isEmpty) {
    return _ClauseMatch(
      nextIndex: startIndex < actualClauses.length ? startIndex + 1 : startIndex,
      errorCount: 1,
      unresolvedCount: 0,
      specificityScore: 0,
      marks: <_LineMarkEntry>[],
      details: <String>['正文分片与词谱不一致。'],
      repeatTexts: <String, _RepeatText>{},
      rhymeFeet: <_RhymeFootMatch>[],
    );
  }

  final actualCharacters = [
    for (final clause in consumed) ...clause.characters,
  ];
  final firstLineNumber = consumed.first.lineNumber;
  var errorCount = 0;
  var unresolvedCount = 0;
  final specificityScore = _alternativeSpecificityScore(alternative);
  final marks = <_LineMarkEntry>[];
  final details = <String>[];
  final repeatBuffers = <String, List<_ActualCharacter>>{};
  final rhymeFeet = <_RhymeFootMatch>[];

  void addCharacterMark(
    _ActualCharacter actual,
    String label,
    ProsodyCheckColor color,
  ) {
    marks.add(
      _LineMarkEntry(
        actual.lineNumber,
        RegulatedVerseMark(
          start: actual.charIndex,
          end: actual.charIndex,
          color: color,
          label: label,
        ),
      ),
    );
  }

  if (actualCharacters.length != alternative.tokens.length) {
    errorCount += 1;
    details.add(
      '${_actualClauseLocation(consumed)}字数不合词谱：'
      '应为 ${alternative.tokens.length} 字，实际 ${actualCharacters.length} 字'
      '（${_actualCharactersText(actualCharacters)}）。',
    );
  }

  final comparableLength = actualCharacters.length < alternative.tokens.length
      ? actualCharacters.length
      : alternative.tokens.length;
  for (var index = 0; index < comparableLength; index += 1) {
    final token = alternative.tokens[index];
    final actual = actualCharacters[index];
    if (token.tone != '中') {
      if (actual.tone != '平' && actual.tone != '仄') {
        unresolvedCount += 1;
      } else if (actual.tone != token.tone) {
        errorCount += 1;
        addCharacterMark(actual, '平仄', ProsodyCheckColor.red);
        details.add(
          '第 ${actual.lineNumber} 行第 ${actual.charIndex} 字“${actual.character}”'
          '平仄不合：应为${token.tone}，实为${actual.tone}。',
        );
      }
    }
    final repeatGroup = token.repeatGroup;
    if (repeatGroup != null && repeatGroup.isNotEmpty) {
      repeatBuffers
          .putIfAbsent(repeatGroup, () => <_ActualCharacter>[])
          .add(actual);
    }
    final rhymeGroup = token.rhymeGroup;
    if (rhymeGroup != null && rhymeGroup.isNotEmpty) {
      rhymeFeet.add(
        _RhymeFootMatch(
          group: rhymeGroup,
          character: actual.character,
          charIndex: actual.charIndex,
          lineNumber: actual.lineNumber,
        ),
      );
    }
  }

  return _ClauseMatch(
    nextIndex: nextIndex,
    errorCount: errorCount,
    unresolvedCount: unresolvedCount,
    specificityScore: specificityScore,
    marks: marks,
    details: details,
    repeatTexts: {
      for (final entry in repeatBuffers.entries)
        entry.key: _RepeatText(
          text: entry.value.map((item) => item.character).join(),
          lineNumber: entry.value.first.lineNumber,
          charCount: entry.value.length,
        ),
    },
    rhymeFeet: rhymeFeet,
  );
}

int _alternativeSpecificityScore(_PatternAlternative alternative) {
  var score = 0;
  for (final token in alternative.tokens) {
    if (token.tone == '平' || token.tone == '仄') {
      score += 2;
    }
    if (token.rhymeGroup != null && token.rhymeGroup!.isNotEmpty) {
      score += 3;
    }
    if (token.repeatGroup != null && token.repeatGroup!.isNotEmpty) {
      score += 1;
    }
  }
  return score;
}

class _RhymeGroupCheck {
  const _RhymeGroupCheck({
    required this.errorCount,
    required this.unresolvedCount,
    required this.distinctRhymeScore,
    required this.primaryRhyme,
    required this.details,
    required this.marks,
  });

  final int errorCount;
  final int unresolvedCount;
  final int distinctRhymeScore;
  final String primaryRhyme;
  final List<String> details;
  final List<_LineMarkEntry> marks;
}

_RhymeGroupCheck _checkRhymeGroups({
  required Poem poem,
  required List<_RhymeFootMatch> feet,
}) {
  var errorCount = 0;
  var unresolvedCount = 0;
  final details = <String>[];
  final marks = <_LineMarkEntry>[];
  final primaryRhymes = <String>{};
  final commonRhymesByGroup = <String, Set<String>>{};
  final grouped = <String, List<_RhymeFootMatch>>{};
  for (final foot in feet) {
    grouped.putIfAbsent(foot.group, () => <_RhymeFootMatch>[]).add(foot);
  }

  for (final entry in grouped.entries) {
    final footMatches = [
      for (final foot in entry.value)
        MapEntry(
          foot,
          _lookupCiPatternRhymeEntries(
            lineNumber: foot.lineNumber,
            character: foot.character,
            rhymeBook: poem.prosodyRhymeBook,
            overridesJson: poem.prosodyOverridesJson,
          ),
        ),
    ];
    if (footMatches.any((item) => item.value.isEmpty)) {
      unresolvedCount += 1;
      final unresolvedFeet = footMatches
          .where((item) => item.value.isEmpty)
          .map((item) => _rhymeFootText(item.key, item.value))
          .join('、');
      details.add('第 ${entry.key} 韵有韵脚尚未收入本地韵表：$unresolvedFeet。');
      continue;
    }
    var common = footMatches.first.value.map((item) => item.label).toSet();
    for (final item in footMatches.skip(1)) {
      common = common.intersection(item.value.map((entry) => entry.label).toSet());
    }
    if (common.isEmpty) {
      errorCount += 1;
      details.add(
        '第 ${entry.key} 韵韵脚不在同一韵部：'
        '${footMatches.map((item) => _rhymeFootText(item.key, item.value)).join('、')}。',
      );
      for (final foot in entry.value) {
        marks.add(
          _LineMarkEntry(
            foot.lineNumber,
            RegulatedVerseMark(
              start: foot.charIndex,
              end: foot.charIndex,
              color: ProsodyCheckColor.red,
              label: '出韵',
            ),
          ),
        );
      }
    } else {
      primaryRhymes.addAll(common);
      commonRhymesByGroup[entry.key] = common;
    }
  }
  final primaryRhyme = primaryRhymes.toList()..sort();

  return _RhymeGroupCheck(
    errorCount: errorCount,
    unresolvedCount: unresolvedCount,
    distinctRhymeScore: _distinctRhymeGroupScore(commonRhymesByGroup),
    primaryRhyme: primaryRhyme.join('、'),
    details: details,
    marks: marks,
  );
}

String _actualClauseLocation(List<_ActualClause> clauses) {
  if (clauses.isEmpty) {
    return '正文附近';
  }
  final lines = clauses.map((item) => item.lineNumber).toSet().toList()..sort();
  if (lines.length == 1) {
    return '第 ${lines.first} 行附近';
  }
  return '第 ${lines.first}-${lines.last} 行附近';
}

String _actualCharactersText(List<_ActualCharacter> characters) {
  return characters.map((item) => item.character).join();
}

String _rhymeFootText(_RhymeFootMatch foot, List<RhymeEntry> matches) {
  final labels = matches.isEmpty
      ? '未收'
      : matches.map((entry) => entry.label).toSet().join('/');
  return '第 ${foot.lineNumber} 行第 ${foot.charIndex} 字“${foot.character}”($labels)';
}

int _distinctRhymeGroupScore(Map<String, Set<String>> commonRhymesByGroup) {
  if (commonRhymesByGroup.length < 2) {
    return 0;
  }
  final groups = commonRhymesByGroup.entries.toList();
  var score = 0;
  for (var i = 0; i < groups.length; i += 1) {
    for (var j = i + 1; j < groups.length; j += 1) {
      final intersection = groups[i].value.intersection(groups[j].value);
      if (intersection.isEmpty) {
        score += 2;
      }
    }
  }
  return score;
}

List<RhymeEntry> _lookupCiPatternRhymeEntries({
  required int lineNumber,
  required String character,
  required String rhymeBook,
  required String overridesJson,
}) {
  final bookMatches = lookupRhymeEntriesForProsodyFoot(
    lineNumber: lineNumber,
    character: character,
    rhymeBook: rhymeBook,
    overridesJson: '',
  );
  if (bookMatches.isNotEmpty) {
    return bookMatches;
  }
  return lookupRhymeEntriesForProsodyFoot(
    lineNumber: lineNumber,
    character: character,
    rhymeBook: rhymeBook,
    overridesJson: overridesJson,
  );
}

String _normalizeTitle(String title) {
  return title
      .replaceAll('《', '')
      .replaceAll('》', '')
      .replaceAll(RegExp(r'\s+'), '')
      .trim();
}

bool _isSentencePunctuation(String char) {
  return char == '，' ||
      char == '。' ||
      char == '！' ||
      char == '？' ||
      char == '；' ||
      char == '、';
}

bool _isChineseRune(int rune) {
  return rune >= 0x4e00 && rune <= 0x9fff;
}
