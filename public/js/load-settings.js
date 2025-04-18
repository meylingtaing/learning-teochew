function set_dark() {
    $('body').addClass('bg-dark');
    $('.navbar').addClass('navbar-dark bg-secondary')
                .removeClass('navbar-light bg-light');
}

function set_light() {
    $('body').removeClass('bg-dark');
    $('.navbar').addClass('navbar-light bg-light')
                .removeClass('navbar-dark bg-secondary');
}

if (localStorage.getItem('darkMode') == '1') {
    set_dark();
}

$('#dark-mode-toggle').click(function() {
    if (localStorage.getItem('darkMode') == '1') {
        localStorage.setItem('darkMode', '0');
        set_light();
    }
    else {
        localStorage.setItem('darkMode', '1');
        set_dark();
    }
});
