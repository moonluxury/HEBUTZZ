"""Reviewed transcription of the output and fill sections in 编程2.docx.

Only these explicit, bounded examples are executed during the offline build.
Document reference code and learner submissions are never executed here.
"""
import contextlib
import io
import itertools

OUTPUTS = [
    (1, "dic = {'a': [1, 2, 3], 'b': [4, 5, 6], 'c': [7, 8, 9]}\nprint(dic['b'][1:])", '[5, 6]', 'python_value'),
    (2, 'print(3 < 5 > 4)', 'True', 'literal'),
    (3, 'print(list(filter(lambda x: x > 2, [0, 1, 2, 3, 0, 0])))', '[3]', 'python_value'),
    (4, 'x = 3\ndef modify():\n    x = 5\nmodify()\nprint(x)', '3', 'literal'),
    (5, 's1 = {1, 3, 5}\ns2 = {4, 5, 6}\nprint(s1 & s2)', '{5}', 'python_value'),
    (6, 'for i in range(3):\n    for s in "abcd":\n        if s == "c":\n            break\n        print(s, end="")', 'ababab', 'literal'),
    (7, 'lst1 = [1, 2, 3, 4, 5]\nlst2 = []\nfor i in lst1:\n    lst2 = [i] + lst2\nprint(lst1[0] + lst2[0])', '6', 'literal'),
    (8, 'lst1 = [1, 2, 3, 4, 5]\nlst2 = []\nfor i in lst1:\n    lst2.append(1)\nprint(lst2[-1])', '1', 'literal'),
    (9, 'a = 123\nb = 456\nprint(a or b)\nprint(a and b)', '123\n456', 'literal'),
    (10, 'lst1 = [1, 2, 3, 4, 5]\nlst2 = [3, 4, 9, 12, 7]\nfor i in range(0, 5):\n    print(i, end="")', '01234', 'literal'),
    (11, 's1 = {1, 3, 5}\ns2 = {4, 5, 6}\nprint(s1 + s2)', 'TypeError', 'literal'),
    (12, "dic = {'a': [1, 2, 3], 'b': [4, 5, 6], 'c': [7, 8, 9]}\nprint(dic['c'][0])", '7', 'literal'),
    (13, 'j = ""\nfor i in "12345":\n    j += i + ","\nprint(j)', '1,2,3,4,5,', 'literal'),
    (14, "dic = {'a': [1, 2, 3], 'b': [4, 5, 6], 'c': [7, 8, 9]}\nprint(sum(dic['a']) + sum(dic['b']))", '21', 'literal'),
    (15, 'def f(a, b):\n    return a + b, a - b\nm, n = f(3, 2)\nprint(m, end="")\nprint(n)', '51', 'literal'),
    (16, 'for i in "CHINA":\n    for k in range(2):\n        print(i, end="")\n        if i == "N":\n            break', 'CCHHIINAA', 'literal'),
    (17, 'def f():\n    a = 3\n    b = 4\n    return a * b\na = 5\nb = 6\nprint(f(), a, b)', '12 5 6', 'literal'),
    (18, 'def f(m):\n    if m % 2 == 1:\n        return 1\n    else:\n        return 0\nif f(9) == 1:\n    print(True)\nelse:\n    print(False)', 'True', 'literal'),
    (19, 'def f(m):\n    return m * 2\nprint(f(1) * f("1"))', '1111', 'literal'),
    (20, 'g = lambda x, y=3, z=5: x * y * z\nprint(g(1))', '15', 'literal'),
    (21, 'for i in reversed(range(10, 0, -2)):\n    print(i, end="")', '246810', 'literal'),
    (22, 'lst = [1, 2, 3, 4, 3, 2, 5, 1, 3]\nn = lst.count(3)\nfor i in range(0, n):\n    lst.remove(3)\nprint(lst[3])', '2', 'literal'),
    (23, 'lst1 = [1, 2, 3, 4, 5]\nlst2 = []\nfor i in lst1:\n    lst2.insert(0, i)\nprint(lst2[-1])', '1', 'literal'),
    (24, 'print(list(filter(None, [0, 1, 2, 3, 0, 0])))', '[1, 2, 3]', 'python_value'),
    (25, 'g = lambda x, y=3, z=5: x * y * z\nprint(g(1, 2))', '10', 'literal'),
    (26, 'def f(m):\n    s = str(m)\n    if s == s[::-1]:\n        return True\n    else:\n        return False\nprint(f(12345))', 'False', 'literal'),
    (27, 'def chanageInt(number2):\n    number2 = number2 + 1\n    print(number2)\nnumber1 = 2\nchanageInt(number1)\nprint(number1)', '3\n2', 'literal'),
    (28, 'def f(a, b):\n    return str(a + b)\nprint(f(1, 2) + f(2, 3))', '35', 'literal'),
    (29, 's1 = {1, 3, 5}\ns2 = {4, 5, 6}\nprint(s1 ^ s2)', '{1, 3, 4, 6}', 'python_value'),
    (30, 'def f1(m):\n    s = 0\n    for i in str(m):\n        s += int(1)\n    return s\ndef f2(n):\n    s = 0\n    while n > 0:\n        s = s + 1\n        n = n // 10\n    return s\nprint(f1(123) // f2(123))', '1', 'literal'),
    (31, 'def f():\n    m = 0\n    m = m + 1\n    print(m, end="")\nf()\nf()', '11', 'literal'),
    (32, 'lst1 = ["abc", "def", "ghi"]\nlst2 = lst1[::-1]\nprint(lst2[1][2])', 'f', 'literal'),
    (33, 'lst1 = [1, 2, 3, 4, 5]\nlst2 = [3, 4, 9, 12, 7]\nfor i in range(0, 5):\n    if lst2[i] % lst1[1] == 0:\n        print(i, end="")', '13', 'literal'),
    (34, 'dic = {(1, 2): 3, (4, 5): 5, (7, 8): 9}\nprint((1, 2) in dic)', 'True', 'literal'),
    (35, 'str1 = "Python example...,wowI"\nstr2 = "exam"\nprint(str1.find(str2, 5))', '7', 'literal'),
]

OUTPUT_NOTES = {
    4: '原题要求求执行语句后 x 的值，末尾增加 print(x) 仅用于展示该值。',
    6: '原参考 aabbcc 与代码不符；内层循环每次输出 ab，三次得到 ababab。',
    8: '按原文 append(1) 保留常量 1，因此结果是 1；原参考 5 与代码不符。',
    9: '原题的两个表达式合并作答，每个结果占一行。',
    10: '原文没有其他循环条件，range(0,5) 输出 01234；原参考 0123 少一项。',
    11: '按原文保留集合相加 s1+s2，Python 不支持该运算。填写异常类型 TypeError；原参考并集不适用。',
    18: '将原文无效的 if f(9)-=1 修复为比较 if f(9)==1。',
    21: 'end="" 不插入空格，输出应为 246810。',
    27: '统一原文 number/numben 拼写，按两条 print 保留换行。',
    30: '按原文保留 int(1)，将损坏的 while n>e 恢复为 n>0。两个函数均返回位数，结果是 1；原参考 2 与该代码不符。',
    33: '按原文保留下标 lst1[1]，符合条件的下标为 1、3；原参考 0123 与代码不符。',
}

# (source start, source answer paragraph, prompt, code, accepted answers, note)
FILLS = [
    (514,515,'计算 s=a+aa+aaa+...，共 n 项。', 'def fun(a, n):\n    s = 0\n    for i in range(1, ____(1)____):\n        s += int(str(a) * i)\n    return s\na, n = eval(input("输入a和n，用逗号分隔："))\ns = fun(____(2)____)\nprint(s)', [['n+1'],['a,n']], '原文末尾打印语句截断，显示结果简化为 print(s)；乘数字符 1 按循环变量 i 修复。'),
    (517,522,'输入一个数，计算各位数字之和。','def fun(n):\n    ____(1)____\n    for i in ____(2)____:\n        sum += int(i)\n    return sum\nn = eval(input("Enter an integer:"))\nsum = fun(n)\nprint("{}各位数之和为：{}".format(____(3)____))', [['sum=0'],['str(n)'],['n,sum']], ''),
    (524,526,'计算 1!+2!+...+10!。','i = 0\nsum = 0\nfac = 1\nwhile ____(1)____:\n    i = i + 1\n    fac = fac * i\n    ____(2)____\nprint(sum)', [['i<10'],['sum+=fac','sum=sum+fac']], '原文 i=1+1 按上下文修复为 i=i+1。'),
    (528,529,'某人口数量为 13 亿，按年增长 0.8% 计算，多少年后达到 26 亿？','n = 13\ny = 0\nwhile ____(1)____:\n    y += 1\n    n = n * (1 + 0.008)\nprint(y)', [['n<26']], ''),
    (531,532,'输入英文，提取不重复的英文字母并按升序输出。','s = input("请输入一段英文：").lower()\nlst = ____(1)____\nfor c in s:\n    if c.isalpha():\n        if c not in lst:\n            lst.____(2)____\nlst.____(3)____\nprint(lst)', [['[]','list()'],['append(c)'],['sort()']], ''),
    (534,535,'计算 1+3+5+...+99。','sum = 0\nfor i in range(1, 101, ____(1)____):\n    sum += i\nprint(sum)', [['2']], ''),
    (537,538,'根据已给定的用户名密码字典 myDict 验证登录。','myDict = ...  # 原资料此处字典内容截断\nusername = input("请输入用户名：")\nif username ____(1)____ myDict:\n    print("该用户不存在！")\nelse:\n    password = input("请输入密码：")\n    if password ____(2)____ myDict[username]:\n        print("密码不正确！")\n    else:\n        print("成功登录！")', [['not in'],['!=']], '原资料字典内容缺失，保留占位提示；这不影响两处运算符填空。'),
    (540,544,'把 list2 合并到 list1，末尾再添加 99 和 100。','list1 = eval(input())\nlist2 = eval(input())\n____(1)____\n____(2)____\nprint(list1)', [['list1+=list2','list1.extend(list2)'],['list1+=[99,100]','list1.extend([99,100])']], ''),
    (546,546,'输出 10 以内的奇数。','for i in range(10):\n    if i % 2 == 0:\n        ____(1)____\n    print(i, end="")', [['continue']], ''),
    (547,549,'输出 100 以内的所有素数。','for n in range(100, 1, -1):\n    for i in range(2, n):\n        if n % i == 0:\n            ____(1)____\n    else:\n        print(n, end=" ")', [['break']], '原文 n%1 按循环因子 i 修复为 n%i。'),
    (551,552,'找出 7 的倍数中十位为 2 的所有三位数。','for x in ____(1)____:\n    if x % 7 == 0 and x // 10 % 10 == 2:\n        print(x)', [['range(100,1000)']], ''),
    (554,557,'补全 prime 函数：n 为素数时返回真，否则返回假。按下列片段填写遇到因子时的语句。','def prime(n):\n    for i in range(2, n):\n        if n % i == 0:\n            ____(1)____\n    return True', [['return False']], '原片段未处理 n<2 的情况；填空按现有片段作答。'),
    (559,561,'判断用户输入的整数是否为素数。','num = int(input())\nif ____(1)____:\n    for i in range(2, num):\n        if ____(2)____:\n            print(False)\n            ____(3)____\n    else:\n        print(True)\nelse:\n    print(False)', [['num>1'],['num%i==0'],['break']], ''),
    (563,564,'输出 Fibonacci 数列前 15 项。','lst = ____(1)____\nfor i in range(2, ____(2)____):\n    lst.____(3)____(lst[i-1] + lst[i-2])\nprint(lst)', [['[1,1]'],['15'],['append']], ''),
    (566,567,'已知 a=3、b=6、c=a*b，用 format 输出 3*6=18。','a = 3\nb = 6\nc = a * b\nprint(____(1)____)', [['"{}*{}={}".format(a,b,c)']], ''),
    (569,571,'统计句子转换成小写后，各字符出现的次数。','sentence = "Life is short,we need Python."\nsentence = sentence.lower()\ncounts = {}\nfor c in sentence:\n    ____(1)____\nprint(counts)', [['counts[c]=sentence.count(c)']], ''),
    (573,574,'使用 format 保留 pi 的两位小数，宽度为 8，右对齐，空位用 = 填充。','pi = 3.1415926\nprint(____(1)____)', [['"{:=>8.2f}".format(pi)']], ''),
    (576,577,'计算 s=1/(2*3)+4/(5*6)+...+28/(29*30)。','sum = 0\ni = 1\nwhile i < 30:\n    sum = sum + i / (i+1) / (i+2)\n    ____(1)____\nprint(sum)', [['i+=3','i=i+3']], '原文多行合并且 sum/s、i/1 混用；按给出的求和式恢复变量与换行。'),
    (579,580,'求下面代码给定列表各元素的三次方之和，存入 Result。','lst = [1, -3, 5, -6, 8, 10]\nlt = []\nfor i in lst:\n    lt.append(i*i*i)\nResult = ____(1)____', [['sum(lt)']], '原题文字末项为 19，而代码末项为 10；本题按所列代码练习，两者不影响本空答案。'),
    (582,586,'统计英文句子中大写字母、小写字母和其他字符的个数。','sentence = input("Please input a sentence:")\nuc = 0\n____(1)____\not = 0\nfor item in ____(2)____:\n    if ____(3)____:\n        uc += 1\n    elif ____(4)____:\n        lc += 1\n    ____(5)____:\n        ot += 1', [['lc=0'],['sentence'],['"A"<=item<="Z"'],['"a"<=item<="z"'],['else']], '原文 uc=8 按计数器初始化修复为 0。'),
    (588,593,'输出前 20 个素数，每行 5 个。','from math import *\nn = 2\n____(1)____\nwhile m < 20:\n    k = trunc(sqrt(n))\n    for i in range(2, ____(2)____):\n        if n % i == 0:\n            ____(3)____\n    else:\n        print(n, end="\\t")\n        ____(4)____\n        if ____(5)____:\n            print()\n    ____(6)____', [['m=0'],['n','k+1'],['break'],['m+=1'],['m%5==0'],['n+=1']], ''),
    (595,596,'根据已给定的学生成绩字典 dic_score，按成绩降序输出姓名。','dic_score = ...  # 原资料字典内容截断\nlstvk = [(v,k) for k,v in ____(1)____]\nprint(lstvk)\nlstvk.sort(____(2)____)\nprint(lstvk)\nfor x in lstvk:\n    print(____(3)____)', [['dic_score.items()'],['reverse=True'],['x[1]']], '原资料具体成绩缺失，未补造学生和分数；三个空均可从给定逻辑确定。'),
    (598,599,'输出 2001—2500 年间所有闰年，每行 8 个。','y = 2001\ncount = 0\nwhile y <= 2500:\n    if y % 4 == 0 and y % 100 != 0 or y % 400 == 0:\n        if ____(1)____:\n            print()\n        print(y, end=" ")\n        count += 1\n    y += 1', [['count%8==0']], '原循环条件及年份判断损坏，按题面范围整理；保留原资料提供的每 8 个换行这一空。'),
    (601,602,'计算 e 的近似值：1+1/1!+1/2!+...+1/20!。','sum = 1\nmul = 1\nfor i in range(1, 21):\n    ____(1)____\n    sum = sum + 1 / mul\nprint(sum)', [['mul*=i','mul=mul*i']], '原参考 mul/=i 有误，应累乘阶乘 mul*=i；求和初值按题面首项 1 修复。'),
    (604,606,'利用函数计算 1!+2!+...+10!。','def jiecheng(____(1)____):\n    r = 1\n    for i in range(1, n+1):\n        r *= i\n    ____(2)____\nsum = 0\nfor i in range(1, 11):\n    rc = ____(3)____\n    sum += rc\nprint(sum)', [['n'],['return r'],['jiecheng(i)']], '原文 r*=1 按阶乘定义修复为 r*=i。'),
]


def verify_outputs():
    for number, code, expected, mode in OUTPUTS:
        output=io.StringIO()
        try:
            with contextlib.redirect_stdout(output):
                exec(compile(code, f'reviewed_output_{number}', 'exec'), {})
            result=output.getvalue().strip()
        except TypeError:
            assert number == 11
            result='TypeError'
        assert result==expected, (number,result,expected)
