#!/bin/bash
# Translate hardcoded Chinese strings in mixmod source to English
# Usage: ./mixmod_translate.sh /path/to/mixmod/source/dir
# The directory should contain mixmod.sp and a mixmod/ subdirectory with includes

MIXMOD_DIR="$1"
if [ -z "$MIXMOD_DIR" ]; then
    echo "Usage: $0 <mixmod-source-dir>"
    exit 1
fi

# ui.sp - Admin menu, password, knife round, live
sed -i \
    -e 's/无法显示地图列表，请联系管理员/Cannot display map list, contact admin/g' \
    -e 's/管理员菜单不可用/Admin menu unavailable/g' \
    -e 's/密码命令已禁用/Password commands disabled/g' \
    -e 's/密码长度已达上限/Password length limit reached/g' \
    -e 's/已设置服务器密码/set the server password/g' \
    -e 's/服务器密码设置为:/Server password set to:/g' \
    -e 's/设置了随机密码/set a random password/g' \
    -e 's/密码已随机设置/Random password has been set/g' \
    -e 's/移除了服务器密码/removed the server password/g' \
    -e 's/服务器密码已刷新，新密码为:/Server password refreshed, new password:/g' \
    -e 's/服务器密码已移除/Server password removed/g' \
    -e 's/开始了满十/started the live match/g' \
    -e 's/重启了回合/restarted the round/g' \
    -e 's/重启回合命令已禁用/Restart round command disabled/g' \
    -e 's/开始了刀局/started the knife round/g' \
    -e 's/刀局功能已禁用/Knife round disabled/g' \
    "$MIXMOD_DIR/ui.sp"

# commands.sp - Ready/unready, spec, mute
sed -i \
    -e 's/准备命令只能由游戏内 T\/CT 真人玩家使用/Ready: only real T\/CT players can ready/g' \
    -e 's/只有 T\/CT 队伍中的真人玩家可以准备/Only real players on T\/CT can ready/g' \
    -e 's/取消准备命令只能由游戏内 T\/CT 真人玩家使用/Unready: only real T\/CT players can unready/g' \
    -e 's/只有 T\/CT 队伍中的真人玩家可以取消准备/Only real players on T\/CT can unready/g' \
    -e 's/无法显示地图列表，请联系管理员/Cannot display map list, contact admin/g' \
    -e 's/管理员已强制所有玩家准备!/Admin force-readied all players!/g' \
    -e 's/用法: !spec <玩家名称\/ID>/Usage: !spec <player name\/ID>/g' \
    -e 's/用法: !mmute <玩家名称\/ID>/Usage: !mmute <player name\/ID>/g' \
    -e 's/用法: !mgag <玩家名称\/ID>/Usage: !mgag <player name\/ID>/g' \
    "$MIXMOD_DIR/commands.sp"

# core.sp - Error messages
sed -i \
    -e 's/无法找到m_iAccount偏移! - 金钱信息将不会显示!/Cannot find m_iAccount offset! - Money info disabled!/g' \
    -e 's/无法找到mp_restartgame变量!/Cannot find mp_restartgame cvar!/g' \
    -e 's/无法找到mp_freezetime变量!/Cannot find mp_freezetime cvar!/g' \
    "$MIXMOD_DIR/core.sp"

# events.sp - Round announcements, knife round results, overtime
sed -i \
    -e 's/恢复购买区成功/Buy zone restored/g' \
    -e 's/第一半场 - 回合: %d, CT分数: %d, T分数: %d/First Half - Round: %d, CT: %d, T: %d/g' \
    -e 's/第二半场 - 回合: %d, CT总分: %d, T总分: %d/Second Half - Round: %d, CT Total: %d, T Total: %d/g' \
    -e 's/比赛结束条件触发: CT=%d, T=%d/Match end triggered: CT=%d, T=%d/g' \
    -e 's/正在重置比赛状态.../Resetting match state.../g' \
    -e 's/\\x0B加时第%d轮 %s半场 - 回合: %d/OT Round %d %s Half - Round: %d/g' \
    -e 's/加时第%d轮 %s半场 - 赛点 for %s/OT Round %d %s Half - Match point for %s/g' \
    -e 's/进攻方队伍赢得了刀局 - 正在进行队伍选择投票.../Attackers won knife round - Team selection vote.../g' \
    -e 's/防守方队伍赢得了刀局 - 正在进行队伍选择投票.../Defenders won knife round - Team selection vote.../g' \
    -e 's/MR3加时赛阶段结束: CT=%d (原始=%d), T=%d (原始=%d)/MR3 Overtime: CT=%d (orig=%d), T=%d (orig=%d)/g' \
    -e 's/加时赛平局，自动进入下一轮MR3加时赛！/OT tied, auto-advancing to next MR3 OT!/g' \
    -e 's/MR3加时赛分出胜负，比赛结束！/MR3 OT decided, match over!/g' \
    -e 's/已满10人！未准备的玩家将在 \\x05%d秒\\x03 后被踢出。请输入 \\x04!r\\x03 准备！/10 players! Unready players kicked in %ds. Type !r to ready!/g' \
    -e 's/已移除 %d 个物品/Removed %d items/g' \
    "$MIXMOD_DIR/events.sp"

# maps.sp - Map list, recording, map vote
sed -i \
    -e 's/无法从maps目录读取地图列表!/Cannot read map list from maps directory!/g' \
    -e 's/地图列表为空! 请联系管理员/Map list empty! Contact admin/g' \
    -e 's/正在更换地图到 \\x04%s/Changing map to %s/g' \
    -e 's/地图名称无效!/Invalid map name!/g' \
    -e 's/正在执行 \\x04%s \\x03.../Executing %s.../g' \
    -e 's/所有玩家的战绩和分数已重置/All player scores and stats have been reset/g' \
    -e 's/执行了 \\x04%s/executed %s/g' \
    -e 's/管理员 \\x04%s \\x03执行了 \\x04%s/Admin %s executed %s/g' \
    -e 's/开始录制比赛 \\x04%s \\x03到文件 \\x04%s/Starting recording %s to file %s/g' \
    -e 's/管理员 \\x04%s \\x03开始录制/Admin %s started recording/g' \
    -e 's/停止录制/Recording stopped/g' \
    -e 's/管理员 \\x04%s \\x03停止录制/Admin %s stopped recording/g' \
    -e 's/未能创建地图列表!/Failed to create map list!/g' \
    -e 's/地图列表为空!/Map list is empty!/g' \
    -e 's/开始地图投票/Starting map vote/g' \
    -e 's/投票结果: \\x04%s\\x03, 准备更换地图.../Vote result: %s, changing map.../g' \
    -e 's/地图投票结束，请所有玩家再次输入 !ready 准备！/Map vote over, all players type !ready to continue!/g' \
    -e 's/管理员 \\x04%s \\x03已设置服务器密码/Admin %s set the server password/g' \
    -e 's/管理员 \\x04%s \\x03移除了服务器密码/Admin %s removed the server password/g' \
    -e 's/管理员 \\x04%s \\x03设置了随机密码/Admin %s set a random password/g' \
    -e 's/管理员 \\x04%s \\x03开始了满十/Admin %s started the live match/g' \
    "$MIXMOD_DIR/maps.sp"

# ready.sp - Ready system messages
sed -i \
    -e 's/条件已改变，取消踢出未准备玩家/Conditions changed, cancelling unready player kick/g' \
    -e 's/已踢出 %d 名未准备的玩家!/Kicked %d unready players!/g' \
    "$MIXMOD_DIR/ready.sp"

# scoring.sp - Score display, MVP
sed -i \
    -e 's/比赛尚未开始/Match has not started/g' \
    -e 's/比赛尚未开始.../Match not started.../g' \
    -e 's/尚未启动!/Not live yet!/g' \
    -e 's/赛点 \\x04for\\x03 %s/Match point for %s/g' \
    -e 's/赛点 \\x04for\\x03 %s - \\x04如果 %s 获胜，将加载Mr3!/Match point for %s - If %s wins, MR3 will load!/g' \
    -e 's/你的本场统计：击杀 \\x04%d\\x03 ，死亡 \\x04%d\\x03/Your stats: Kills %d, Deaths %d/g' \
    -e 's/尝试查找MVP玩家时出错.../Error finding MVP.../g' \
    -e 's/击杀统计:/Kill stats:/g' \
    -e 's/MVP数据显示已禁用/MVP data display disabled/g' \
    -e 's/MVP尚未产生，请稍候/MVP not yet determined, wait/g' \
    "$MIXMOD_DIR/scoring.sp"

echo "Mixmod translated: $(find "$MIXMOD_DIR" -name '*.sp' | wc -l) files patched"
