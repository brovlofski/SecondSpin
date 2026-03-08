#!/usr/bin/env python3
"""
为知笔记批量导出与内容分析工具

此脚本用于批量导出为知笔记笔记并进行内容分析。
为知笔记通常将数据存储在以下位置之一：
1. macOS: ~/Documents/WizNote 或 ~/Library/Application Support/WizNote
2. Windows: %USERPROFILE%\Documents\WizNote 或 %APPDATA%\WizNote
3. Linux: ~/.local/share/WizNote 或 ~/Documents/WizNote

如果没有找到笔记数据库，用户需要先从为知笔记手动导出笔记为HTML或TXT格式。
"""

import os
import sys
import re
import json
import sqlite3
import argparse
import logging
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Tuple, Optional, Any
from collections import Counter
import html
from html.parser import HTMLParser

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)


class WizNoteAnalyzer:
    """为知笔记分析器"""
    
    def __init__(self, data_dir: Optional[str] = None):
        """初始化分析器"""
        self.data_dir = data_dir
        self.notes: List[Dict] = []
        self.export_dir = Path.cwd() / "wiznote_export"
        self.export_dir.mkdir(exist_ok=True)
        
        # 尝试查找为知笔记数据目录
        if not data_dir:
            self.data_dir = self.find_wiznote_data_dir()
        
    def find_wiznote_data_dir(self) -> Optional[str]:
        """查找为知笔记数据目录"""
        possible_paths = [
            # macOS
            Path.home() / "Documents" / "WizNote",
            Path.home() / "Library" / "Application Support" / "WizNote",
            # Windows/Linux
            Path.home() / ".wiznote",
            Path.home() / ".local" / "share" / "WizNote",
        ]
        
        for path in possible_paths:
            if path.exists():
                logger.info(f"找到为知笔记数据目录: {path}")
                return str(path)
        
        logger.warning("未找到为知笔记数据目录，请手动指定")
        return None
    
    def find_wiznote_database(self) -> Optional[str]:
        """查找为知笔记数据库文件"""
        if not self.data_dir:
            return None
            
        db_paths = [
            Path(self.data_dir) / "data" / "index.db",
            Path(self.data_dir) / "WizNote.db",
            Path(self.data_dir) / "wiznote.db",
        ]
        
        for db_path in db_paths:
            if db_path.exists():
                logger.info(f"找到为知笔记数据库: {db_path}")
                return str(db_path)
        
        return None
    
    def extract_from_database(self, db_path: str) -> List[Dict]:
        """从SQLite数据库提取笔记"""
        notes = []
        try:
            conn = sqlite3.connect(db_path)
            cursor = conn.cursor()
            
            # 查询笔记（表结构可能因版本而异）
            cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
            tables = cursor.fetchall()
            logger.info(f"数据库中的表: {tables}")
            
            # 尝试常见的表名
            table_queries = [
                ("SELECT * FROM WIZ_DOCUMENT", "WIZ_DOCUMENT"),
                ("SELECT * FROM DOCUMENTS", "DOCUMENTS"),
                ("SELECT * FROM NOTES", "NOTES"),
            ]
            
            for query, table_name in table_queries:
                try:
                    cursor.execute(query)
                    columns = [description[0] for description in cursor.description]
                    rows = cursor.fetchall()
                    
                    if rows:
                        logger.info(f"从表 {table_name} 找到 {len(rows)} 条记录")
                        # 转换为字典列表
                        for row in rows:
                            note = dict(zip(columns, row))
                            notes.append(note)
                        break
                except sqlite3.Error as e:
                    logger.debug(f"查询表 {table_name} 失败: {e}")
            
            conn.close()
            
        except Exception as e:
            logger.error(f"读取数据库失败: {e}")
        
        return notes
    
    def export_to_markdown(self, notes: List[Dict], output_dir: Path):
        """导出笔记为Markdown格式"""
        logger.info(f"导出 {len(notes)} 条笔记到 {output_dir}")
        
        for i, note in enumerate(notes, 1):
            # 提取基本信息
            title = note.get('title', f'Untitled Note {i}')
            content = note.get('content', '')
            created = note.get('created', datetime.now())
            modified = note.get('modified', datetime.now())
            
            # 清理文件名
            safe_title = re.sub(r'[^\w\s-]', '', title).strip()
            safe_title = re.sub(r'[-\s]+', '-', safe_title)
            if not safe_title:
                safe_title = f'note-{i}'
            
            # 创建Markdown文件
            md_content = f"""# {title}

**创建时间**: {created}
**修改时间**: {modified}

{content}
"""
            
            filepath = output_dir / f"{safe_title}.md"
            with open(filepath, 'w', encoding='utf-8') as f:
                f.write(md_content)
            
            if i % 10 == 0:
                logger.info(f"已导出 {i}/{len(notes)} 条笔记")
    
    def export_to_html(self, notes: List[Dict], output_dir: Path):
        """导出笔记为HTML格式"""
        logger.info(f"导出 {len(notes)} 条笔记到HTML格式")
        
        # 创建索引文件
        index_content = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>为知笔记导出</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; line-height: 1.6; max-width: 800px; margin: 0 auto; padding: 20px; }
        h1 { color: #333; border-bottom: 2px solid #eee; padding-bottom: 10px; }
        .note { border: 1px solid #ddd; border-radius: 5px; padding: 15px; margin-bottom: 20px; background: #f9f9f9; }
        .note-title { margin-top: 0; color: #2c3e50; }
        .meta { color: #7f8c8d; font-size: 0.9em; margin-bottom: 10px; }
        .content { margin-top: 15px; }
        .stats { background: #f8f9fa; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
    </style>
</head>
<body>
    <h1>为知笔记导出</h1>
    <div class="stats">
        <p>总笔记数: {{note_count}}</p>
        <p>导出时间: {{export_time}}</p>
    </div>
"""
        
        for i, note in enumerate(notes, 1):
            title = note.get('title', f'Untitled Note {i}')
            content = note.get('content', '')
            created = note.get('created', '')
            modified = note.get('modified', '')
            
            # 转义HTML
            title_escaped = html.escape(str(title))
            content_escaped = html.escape(str(content))
            
            index_content += f"""
    <div class="note">
        <h2 class="note-title">{title_escaped}</h2>
        <div class="meta">
            <strong>创建:</strong> {created} | <strong>修改:</strong> {modified}
        </div>
        <div class="content">
            {content_escaped.replace(chr(10), '<br>')}
        </div>
    </div>
"""
        
        index_content += """
</body>
</html>
"""
        
        # 替换占位符
        index_content = index_content.replace('{{note_count}}', str(len(notes)))
        index_content = index_content.replace('{{export_time}}', datetime.now().strftime('%Y-%m-%d %H:%M:%S'))
        
        # 写入文件
        index_file = output_dir / "index.html"
        with open(index_file, 'w', encoding='utf-8') as f:
            f.write(index_content)
        
        logger.info(f"HTML索引文件已创建: {index_file}")
    
    def analyze_content(self, notes: List[Dict]) -> Dict[str, Any]:
        """分析笔记内容"""
        logger.info(f"开始分析 {len(notes)} 条笔记")
        
        # 基本统计
        total_chars = 0
        total_words = 0
        all_text = []
        titles = []
        
        for note in notes:
            title = str(note.get('title', ''))
            content = str(note.get('content', ''))
            
            titles.append(title)
            all_text.append(content)
            
            total_chars += len(content)
            # 简单的中英文单词计数
            words = re.findall(r'[\u4e00-\u9fff]+|[a-zA-Z]+', content)
            total_words += len(words)
        
        # 合并所有文本进行分析
        full_text = ' '.join(all_text)
        
        # 中文文本分析
        chinese_chars = re.findall(r'[\u4e00-\u9fff]', full_text)
        english_words = re.findall(r'[a-zA-Z]+', full_text)
        
        # 关键词提取（简单版）
        word_freq = Counter(chinese_chars + english_words)
        top_keywords = word_freq.most_common(20)
        
        # 主题分析（基于高频词）
        common_chinese_words = [char for char, count in word_freq.most_common(50) 
                               if re.match(r'[\u4e00-\u9fff]', char) and count > 1]
        
        # 时间分析（如果有时间信息）
        date_patterns = [
            r'\d{4}-\d{2}-\d{2}',
            r'\d{4}年\d{1,2}月\d{1,2}日',
            r'\d{1,2}/\d{1,2}/\d{4}'
        ]
        
        dates_found = []
        for pattern in date_patterns:
            dates_found.extend(re.findall(pattern, full_text))
        
        analysis_result = {
            'total_notes': len(notes),
            'total_characters': total_chars,
            'total_words': total_words,
            'average_chars_per_note': total_chars // max(1, len(notes)),
            'average_words_per_note': total_words // max(1, len(notes)),
            'chinese_char_count': len(chinese_chars),
            'english_word_count': len(english_words),
            'top_keywords': top_keywords,
            'common_chinese_words': common_chinese_words[:20],
            'dates_found_count': len(dates_found),
            'dates_found': list(set(dates_found))[:10],  # 去重并取前10
            'titles': titles[:10],  # 前10个标题
            'note_with_most_chars': max(notes, key=lambda x: len(str(x.get('content', ''))), default={}).get('title', 'N/A'),
            'note_with_least_chars': min(notes, key=lambda x: len(str(x.get('content', ''))), default={}).get('title', 'N/A'),
        }
        
        return analysis_result
    
    def save_analysis_report(self, analysis: Dict[str, Any], output_dir: Path):
        """保存分析报告"""
        report_file = output_dir / "analysis_report.json"
        
        with open(report_file, 'w', encoding='utf-8') as f:
            json.dump(analysis, f, ensure_ascii=False, indent=2, default=str)
        
        # 同时创建易读的文本报告
        text_report = output_dir / "analysis_report.txt"
        with open(text_report, 'w', encoding='utf-8') as f:
            f.write("=" * 60 + "\n")
            f.write("为知笔记内容分析报告\n")
            f.write("=" * 60 + "\n\n")
            
            f.write(f"📊 基本统计\n")
            f.write(f"总笔记数: {analysis['total_notes']}\n")
            f.write(f"总字符数: {analysis['total_characters']:,}\n")
            f.write(f"总词数: {analysis['total_words']:,}\n")
            f.write(f"平均每笔记字符数: {analysis['average_chars_per_note']:,}\n")
            f.write(f"平均每笔记词数: {analysis['average_words_per_note']:,}\n\n")
            
            f.write(f"🔤 语言统计\n")
            f.write(f"中文字符数: {analysis['chinese_char_count']:,}\n")
            f.write(f"英文单词数: {analysis['english_word_count']:,}\n\n")
            
            f.write(f"🏆 最高频关键词（前20）\n")
            for word, count in analysis['top_keywords']:
                f.write(f"  {word}: {count}次\n")
            f.write("\n")
            
            f.write(f"📅 日期信息\n")
            f.write(f"找到的日期数量: {analysis['dates_found_count']}\n")
            if analysis['dates_found']:
                f.write(f"示例日期: {', '.join(analysis['dates_found'][:5])}\n")
            f.write("\n")
            
            f.write(f"📝 笔记标题（前10）\n")
            for i, title in enumerate(analysis['titles'], 1):
                f.write(f"{i}. {title}\n")
            f.write("\n")
            
            f.write(f"📈 其他信息\n")
            f.write(f"字符最多的笔记: {analysis['note_with_most_chars']}\n")
            f.write(f"字符最少的笔记: {analysis['note_with_least_chars']}\n")
            
            f.write("\n" + "=" * 60 + "\n")
            f.write("报告生成时间: " + datetime.now().strftime('%Y-%m-%d %H:%M:%S') + "\n")
            f.write("=" * 60 + "\n")
        
        logger.info(f"分析报告已保存: {report_file}")
        logger.info(f"文本报告已保存: {text_report}")
    
    def process_manual_export(self, input_dir: str):
        """处理手动导出的笔记文件"""
        input_path = Path(input_dir)
        if not input_path.exists():
            logger.error(f"输入目录不存在: {input_dir}")
            return []
        
        notes = []
        supported_extensions = {'.html', '.htm', '.txt', '.md', '.pdf'}
        
        for file_path in input_path.rglob('*'):
            if file_path.is_file() and file_path.suffix.lower() in supported_extensions:
                try:
                    with open(file_path, 'r', encoding='utf-8') as f:
                        content = f.read()
                    
                    note = {
                        'title': file_path.stem,
                        'content': content,
                        'filename': file_path.name,
                        'path': str(file_path),
                        'created': datetime.fromtimestamp(file_path.stat().st_ctime),
                        'modified': datetime.fromtimestamp(file_path.stat().st_mtime),
                    }
                    notes.append(note)
                    
                except Exception as e:
                    logger.warning(f"读取文件 {file_path} 失败: {e}")
        
        logger.info(f"从手动导出目录找到 {len(notes)} 个笔记文件")
        return notes
    
    def run(self, mode: str = 'auto', input_dir: Optional[str] = None):
        """运行分析工具"""
        logger.info("开始为知笔记导出与分析")
        
        notes = []
        
        if mode == 'auto' or mode == 'database':
            # 尝试从数据库提取
            db_path = self.find_wiznote_database()
            if db_path:
                notes = self.extract_from_database(db_path)
                if notes:
                    logger.info(f"从数据库成功提取 {len(notes)} 条笔记")
        
        if (not notes) and input_dir:
            # 从手动导出目录处理
            notes = self.process_manual_export(input_dir)
        
        if not notes:
            logger.error("未找到任何笔记，请检查数据源")
            logger.info("""
            使用说明：
            1. 如果已安装为知笔记，请确保数据目录存在
            2. 或者，先从为知笔记手动导出笔记为HTML/TXT格式，然后指定导出目录
            3. 支持的导出格式：HTML、TXT、MD、PDF
            """)
            return
        
        # 导出笔记
        logger.info(f"准备导出 {len(notes)} 条笔记")
        
        # 导出为Markdown
        md_dir = self.export_dir / "markdown"
        md_dir.mkdir(exist_ok=True)
        self.export_to_markdown(notes, md_dir)
        
        # 导出为HTML
        html_dir = self.export_dir / "html"
        html_dir.mkdir(exist_ok=True)
        self.export_to_html(notes, html_dir)
        
        # 分析内容
        analysis = self.analyze_content(notes)
        
        # 保存分析报告
        report_dir = self.export_dir / "reports"
        report_dir.mkdir(exist_ok=True)
        self.save_analysis_report(analysis, report_dir)
        
        # 打印摘要
        print("\n" + "="*60)
        print("✅ 导出与分析完成!")
        print("="*60)
        print(f"📁 导出目录: {self.export_dir}")
        print(f"📄 Markdown导出: {md_dir} ({len(notes)} 个文件)")
        print(f"🌐 HTML导出: {html_dir} (index.html)")
        print(f"📊 分析报告: {report_dir}")
        print("\n📈 分析摘要:")
        print(f"   总笔记数: {analysis['total_notes']}")
        print(f"   总字符数: {analysis['total_characters']:,}")
        print(f"   总词数: {analysis['total_words']:,}")
        print(f"   中文字符: {analysis['chinese_char_count']:,}")
        print(f"   高频关键词: {', '.join([w for w, _ in analysis['top_keywords'][:5]])}")
        print("="*60)


def main():
    """主函数"""
    parser = argparse.ArgumentParser(
        description='为知笔记批量导出与内容分析工具',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用示例:
  1. 自动查找并分析为知笔记:
     python wiznote_export_analyzer.py --mode auto
  
  2. 分析手动导出的笔记文件:
     python wiznote_export_analyzer.py --mode manual --input ~/Downloads/wiz_export
  
  3. 指定为知笔记数据目录:
     python wiznote_export_analyzer.py --data-dir ~/Documents/WizNote
  
  4. 导出到自定义目录:
     python wiznote_export_analyzer.py --output ./my_export
        """
    )
    
    parser.add_argument('--mode', choices=['auto', 'database', 'manual'], default='auto',
                       help='运行模式: auto=自动检测, database=仅从数据库, manual=手动导出文件')
    parser.add_argument('--data-dir', help='为知笔记数据目录路径')
    parser.add_argument('--input', help='手动导出笔记的目录路径')
    parser.add_argument('--output', help='导出文件输出目录')
    parser.add_argument('--verbose', action='store_true', help='显示详细日志')
    
    args = parser.parse_args()
    
    # 设置日志级别
    if args.verbose:
        logger.setLevel(logging.DEBUG)
    
    # 创建分析器
    analyzer = WizNoteAnalyzer(args.data_dir)
    
    # 设置输出目录
    if args.output:
        analyzer.export_dir = Path(args.output)
        analyzer.export_dir.mkdir(parents=True, exist_ok=True)
    
    # 运行分析
    analyzer.run(mode=args.mode, input_dir=args.input)


if __name__ == '__main__':
    main()