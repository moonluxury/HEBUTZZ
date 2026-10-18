# HEBUTZZ
河工开物开发

现有六个题库：马克思主义原理、毛泽东思想和中国特色社会主义、习近平新时代中国特色社会主义思想概论、MATLAB（505 题）、Python（890 题）和 C++（402 题）。错题数显示在错题库各课程按钮右侧，Main 页面不再显示；答题页统一文字样式，支持工大蓝搜索按钮和白色镂空搜索图标。

Python 题库现有 890 道文字题，保留原资料的题目版本与题号。图片选择题、成绩表、公式和星号图形均已转写；部分原资料缺漏或答案争议会在参考说明中注明。

Windows 64 位版的编程编辑器支持运行 Python 代码。需要 `input()` 的程序，请先在“输入数据”中按行填写；输出和错误显示在编辑器下方。单次运行限制为 10 秒，支持手动停止，输出超过 256 KB 会终止。参考代码可以展开和收起，运行或查看参考代码不会自动判题；需要复习的编程题可用底部按钮加入错题库。

运行环境使用内置的 CPython 3.13.16 Windows embeddable package，首次运行自动解压，无需另行安装 Python。压缩包内含 Python 许可证，SHA-256 为 `97dae5274cc54867065e8d5a3226e48c35017ed332a0fdb0e27d5b5821961297`。下载来源：[Python 官方发行目录](https://www.python.org/ftp/python/3.13.16/python-3.13.16-embed-amd64.zip)。该功能执行本机代码，不是安全沙箱；当前不提供第三方包安装或 Android 运行支持。

题库构建：`python tools/replace_python_bank.py`。转写内容保存在 `tools/python_choice_transcriptions.json`，不再需要题目截图资源。

隔离检查：`python tools/run_quiz_checks.py --godot <Godot控制台程序路径> --course python`，覆盖题库、实际代码运行、草稿、错题与其他课程回归，不改动学习记录。
