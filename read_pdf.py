import PyPDF2
import sys

def read_pdf(file_path):
    with open('output.txt', 'w', encoding='utf-8') as f:
        with open(file_path, 'rb') as file:
            reader = PyPDF2.PdfReader(file)
            for page_num in range(len(reader.pages)):
                page = reader.pages[page_num]
                f.write(f"--- Page {page_num + 1} ---\n")
                f.write(page.extract_text() + "\n")

if __name__ == "__main__":
    read_pdf('e:\\lunara_app\\lunara_app\\LUNARA SUBCRIPCTIONS.pdf')
