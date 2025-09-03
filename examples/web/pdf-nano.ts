export enum PageFormat {
    LETTER,
    A4
};

export enum PageOrientation {
    PORTRAIT,
    LANDSCAPE
};

export enum Font {
    ARIAL_REGULAR = 1,
    ARIAL_BOLD,
    COURIER
};

export enum TextAlignment {
    LEFT,
    CENTERED,
    RIGHT
};

export class PDFDocument {
    private static wasmInstance: WebAssembly.Instance;
    private static get memory(): Uint8Array {
        return new Uint8Array((<any>this.wasmInstance.exports['memory'])['buffer']);
    }

    private handle: number;
    private get view(): DataView {
        return new DataView(PDFDocument.memory.buffer);
    }

    static async loadWasm(wasm: Blob) {
        const buf = await wasm.arrayBuffer();
        this.wasmInstance = (await WebAssembly.instantiate(buf, { env: {} })).instance;
    }

    static getVersion(): string {
        const outPtr = (<any>PDFDocument.wasmInstance.exports['getVersion'])();
        let end = outPtr;
        const array = PDFDocument.memory;
        while (array.at(end) != 0) {
            end++;
        }
        return new TextDecoder().decode(PDFDocument.memory.slice(outPtr, end));
    }

    constructor() {
        this.handle = (<any>PDFDocument.wasmInstance.exports['createEncoder'])(PageFormat.A4, PageOrientation.PORTRAIT);
    }

    destroy() {
        this.callH('freeEncoder');
    }

    showPageNumbers(alignment: TextAlignment, fontSize: number) {
        this.callH('showPageNumbers', alignment, fontSize);
    }

    advanceCursor(dots: number) {
        this.callH('advanceCursor', dots);
    }

    setFont(font: Font) {
        this.callH('setFont', font);
    }

    setFontSize(size: number) {
        this.callH('setFontSize', size);
    }

    addHorizontalLine(thickness: number) {
        this.callH('addHorizontalLine', thickness);
    }

    addText(text: string) {
        const strPtr = this.allocAndEncodeString(text);
        this.callH('addText', strPtr);
        this.free(strPtr);
    }

    startTable(columnWidths: number[]) {
        const ptr = this.alloc(2*columnWidths.length);
        columnWidths.forEach((v,i) => this.view.setUint16(ptr + 2*i, v, true));
        this.callH('startTable', ptr, columnWidths.length);
        this.free(ptr);
    }

    setTableHeader(headers: string[], repeatHeaders: boolean) {
        const ptr = this.alloc(4*headers.length);
        headers.forEach((v, i) => {
            const str = this.allocAndEncodeString(v);
            this.view.setUint32(ptr + 4*i, str, true)
        });

        this.callH('setTableHeaders', ptr, headers.length, repeatHeaders);

        headers.forEach((v, i) => this.free(this.view.getUint32(ptr + 4*i, true)));
        this.free(ptr);
    }

    addTableRow(columns: string[]) {
        const ptr = this.alloc(4*columns.length);
        columns.forEach((v, i) => {
            const str = this.allocAndEncodeString(v);
            this.view.setUint32(ptr + 4*i, str, true)
        });

        this.callH('writeRow', ptr, columns.length);

        columns.forEach((v, i) => this.free(this.view.getUint32(ptr + 4*i, true)));
        this.free(ptr);
    }

    finishTable() {
        this.callH('finishTable');
    }

    breakPage() {
        this.callH('breakPage');
    }

    setTextAlignment(alignment: TextAlignment) {
        this.callH('setTextAlignment', alignment);
    }

    setFontColor(r: number, g: number, b: number) {
        this.callH('setFontColor', r, g, b);
    }

    setFillColor(r: number, g: number, b: number) {
        this.callH('setFillColor', r, g, b);
    }   

    setStrokeColor(r: number, g: number, b: number) {
        this.callH('setStrokeColor', r, g, b);
    }

    render(): Uint8Array {
        const outPtr = this.callH('render');
        if (outPtr == 0) {
            throw "Rendering PDF failed";
        }
        let end = outPtr;
        const array = PDFDocument.memory;
        while (array.at(end) != 0) {
            end++;
        }
        return PDFDocument.memory.slice(outPtr, end);
    }

    getVersion(): string {
        const outPtr = (<any>PDFDocument.wasmInstance.exports['getVersion'])();
        let end = outPtr;
        const array = PDFDocument.memory;
        while (array.at(end) != 0) {
            end++;
        }
        return new TextDecoder().decode(PDFDocument.memory.slice(outPtr, end));
    }

    private allocAndEncodeString(text: string): number {
        // https://developer.mozilla.org/en-US/docs/Web/API/TextEncoder/encodeInto
        text += '\0';
        const nBytes = text.length*3;
        const strPtr = this.alloc(nBytes);
        new TextEncoder().encodeInto(text, PDFDocument.memory.subarray(strPtr, strPtr + nBytes));
        return strPtr;
    }

    private alloc(size: number): number {
        return this.call('alloc', size);
    }

    private free(ptr: number) {
        this.call('free', ptr);
    }

    private callH(functionName: string, ...args: any[]): any {
        return this.call(functionName, this.handle, ...args);
    }

    private call(functionName: string, ...args: any[]): any {
        const result = (<any>PDFDocument.wasmInstance.exports[functionName])(...args);
        if (result == -1) {
            throw "Error while generating PDF @" + functionName; 
        }
        return result;
    }
}