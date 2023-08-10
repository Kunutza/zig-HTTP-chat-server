// Enable submit button only when there is a value
const input = document.querySelector('input[id="text"]');
const sub_text_btn = document.querySelector('button[id="sub_text_btn"]');

sub_text_btn.disabled = true;
input.addEventListener('input', function (event) {
    if (event.target.validity.valueMissing) {
        sub_text_btn.disabled = true;
    } else {
        sub_text_btn.disabled = false;
    }
})
