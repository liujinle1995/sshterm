import 'package:flutter/foundation.dart';

/// 一条可直接丢进终端的常用 Linux 命令。
///
/// 手机上敲 `journalctl -xeu docker --no-pager` 是酷刑，所以做成一键发送。
@immutable
class CommandSnippet {
  const CommandSnippet({
    required this.id,
    required this.name,
    required this.command,
    this.category = '常用',
    this.newline = true,
    this.note,
  });

  final String id;

  /// 短标题，显示在 chip 上
  final String name;

  /// 实际发送的文本。**不含**结尾换行，由 [newline] 控制。
  final String command;

  /// 分组名，管理页按它分区
  final String category;

  /// true = 发送后补一个回车（立即执行）；false = 只粘进去，让用户补参数
  final bool newline;

  /// 说明，编辑弹窗里会显示
  final String? note;

  CommandSnippet copyWith({
    String? name,
    String? command,
    String? category,
    bool? newline,
    String? note,
    bool clearNote = false,
  }) {
    return CommandSnippet(
      id: id,
      name: name ?? this.name,
      command: command ?? this.command,
      category: category ?? this.category,
      newline: newline ?? this.newline,
      note: clearNote ? null : (note ?? this.note),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'command': command,
    'category': category,
    'newline': newline,
    'note': note,
  };

  factory CommandSnippet.fromJson(Map<String, dynamic> json) {
    return CommandSnippet(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      command: json['command'] as String? ?? '',
      category: json['category'] as String? ?? '常用',
      newline: json['newline'] as bool? ?? true,
      note: json['note'] as String?,
    );
  }

  static String newId() =>
      'c${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  /// 预设命令库。都是只读无害或常规运维命令，执行前不需要用户补参数的排前面。
  static List<CommandSnippet> get defaults => <CommandSnippet>[
    // ---- 系统状态
    const CommandSnippet(
      id: 's01',
      name: '资源占用',
      command: 'top -b -n 1 | head -20',
      category: '系统',
      note: 'CPU / 内存占用最高的几个进程',
    ),
    const CommandSnippet(
      id: 's02',
      name: '磁盘剩余',
      command: 'df -h',
      category: '系统',
    ),
    const CommandSnippet(
      id: 's03',
      name: '当前目录体积',
      command: 'du -sh ./* 2>/dev/null | sort -hr | head -20',
      category: '系统',
      note: '谁在吃空间，一眼看出来',
    ),
    const CommandSnippet(
      id: 's04',
      name: '内存详情',
      command: 'free -h',
      category: '系统',
    ),
    const CommandSnippet(
      id: 's05',
      name: '系统信息',
      command: 'uname -a && cat /etc/os-release | head -3',
      category: '系统',
    ),
    const CommandSnippet(
      id: 's06',
      name: '开机时长',
      command: 'uptime',
      category: '系统',
    ),

    // ---- 进程 / 服务
    const CommandSnippet(
      id: 'p01',
      name: '进程全览',
      command: 'ps aux --sort=-%mem | head -20',
      category: '进程',
    ),
    const CommandSnippet(
      id: 'p02',
      name: '按名找进程',
      command: 'ps aux | grep -i ',
      category: '进程',
      newline: false,
      note: '不回车，留着让你补进程名',
    ),
    const CommandSnippet(
      id: 'p03',
      name: '服务状态',
      command: 'systemctl status ',
      category: '进程',
      newline: false,
    ),
    const CommandSnippet(
      id: 'p04',
      name: '看服务日志',
      command: 'journalctl -xeu ',
      category: '进程',
      newline: false,
      note: '补上服务名后回车',
    ),
    const CommandSnippet(
      id: 'p05',
      name: '实时日志',
      command: 'journalctl -f',
      category: '进程',
      note: 'Ctrl+C 退出跟随',
    ),

    // ---- 网络
    const CommandSnippet(
      id: 'n01',
      name: '监听端口',
      command: 'ss -tulnp',
      category: '网络',
    ),
    const CommandSnippet(
      id: 'n02',
      name: '网卡地址',
      command: 'ip -br addr',
      category: '网络',
    ),
    const CommandSnippet(
      id: 'n03',
      name: '路由表',
      command: 'ip route',
      category: '网络',
    ),
    const CommandSnippet(
      id: 'n04',
      name: '测连通',
      command: 'ping -c 4 ',
      category: '网络',
      newline: false,
    ),
    const CommandSnippet(
      id: 'n05',
      name: '出口 IP',
      command: 'curl -fsS ifconfig.me',
      category: '网络',
    ),

    // ---- 文件
    const CommandSnippet(
      id: 'f01',
      name: '详细列表',
      command: 'ls -lah',
      category: '文件',
    ),
    const CommandSnippet(
      id: 'f02',
      name: '找文件',
      command: 'find / -name ',
      category: '文件',
      newline: false,
    ),
    const CommandSnippet(
      id: 'f03',
      name: '内容搜索',
      command: 'grep -rn "" . 2>/dev/null | head -30',
      category: '文件',
      newline: false,
      note: '把光标放进引号里再写关键词',
    ),
    const CommandSnippet(
      id: 'f04',
      name: '跟踪日志尾部',
      command: 'tail -f ',
      category: '文件',
      newline: false,
    ),
    const CommandSnippet(
      id: 'f05',
      name: '查看尾部',
      command: 'tail -n 50 ',
      category: '文件',
      newline: false,
    ),

    // ---- Docker
    const CommandSnippet(
      id: 'd01',
      name: '容器列表',
      command: 'docker ps -a',
      category: '容器',
    ),
    const CommandSnippet(
      id: 'd02',
      name: '容器日志',
      command: 'docker logs -f --tail 100 ',
      category: '容器',
      newline: false,
    ),
    const CommandSnippet(
      id: 'd03',
      name: '进容器',
      command: 'docker exec -it ',
      category: '容器',
      newline: false,
      note: '后面补 容器名 sh',
    ),
    const CommandSnippet(
      id: 'd04',
      name: '资源占用',
      command: 'docker stats --no-stream',
      category: '容器',
    ),
    const CommandSnippet(
      id: 'd05',
      name: '清理悬空镜像',
      command: 'docker image prune -f',
      category: '容器',
    ),

    // ---- 常用操作
    const CommandSnippet(
      id: 'u01',
      name: '更新软件源',
      command: 'sudo apt update',
      category: '运维',
    ),
    const CommandSnippet(
      id: 'u02',
      name: '清屏',
      command: 'clear',
      category: '运维',
    ),
    const CommandSnippet(
      id: 'u03',
      name: '历史命令',
      command: 'history | tail -30',
      category: '运维',
    ),
    const CommandSnippet(
      id: 'u04',
      name: '当前路径',
      command: 'pwd',
      category: '运维',
    ),
    const CommandSnippet(
      id: 'u05',
      name: '回到主目录',
      command: 'cd ~',
      category: '运维',
    ),
  ];
}
